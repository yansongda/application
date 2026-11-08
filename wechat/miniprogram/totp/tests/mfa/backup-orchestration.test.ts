/**
 * 导出/导入编排测试（mock api，不触碰 wx.*）：
 * 缺 secret 跳过、批内/本地去重、单条 invalid、§6.2 冒号重建与校正、失败继续、取消保留已成功。
 */
import { describe, expect, it } from "bun:test";
import { encryptEnvelope } from "../../src/backup/crypto";
import type { BackupItem } from "../../src/backup/payload";
import { BackupErrorCode } from "../../src/backup/spec";
import { buildExport } from "../../src/models/backup/exporter";
import {
  analyze,
  type ImportApi,
  planUriIssuer,
  run,
} from "../../src/models/backup/importer";
import type { CacheItem, Item } from "../../src/types/totp";

const SECRET = "JBSWY3DPEHPK3PXP";
const PASSWORD = "TestPassword123";

const ITEM = (
  issuer: string,
  username: string,
  secret = SECRET,
): BackupItem => ({
  issuer,
  username,
  secret,
  period: 30,
  digits: 6,
  algorithm: "SHA1",
  tags: [],
  pinned: false,
});

const CACHE_ITEM = (
  issuer: string,
  username: string,
  secret: string,
): CacheItem => ({
  id: `${issuer}-${username}`,
  issuer,
  username,
  secret,
  period: 30,
  digits: 6,
  algorithm: "SHA1",
  tags: [],
  pinned: false,
});

const deterministicRng = (): ((length: number) => Promise<Uint8Array>) => {
  let counter = 0;

  return async (length: number): Promise<Uint8Array> => {
    const bytes = new Uint8Array(length);

    for (let i = 0; i < length; i++) {
      bytes[i] = counter & 0xff;
      counter += 1;
    }

    return bytes;
  };
};

const encryptItems = async (items: BackupItem[]): Promise<string> => {
  const result = await encryptEnvelope(items, PASSWORD, {
    source: "wechat",
    app: "1.2.0",
    rng: deterministicRng(),
    iterations: 10000,
  });

  return result.text;
};

interface ApiCalls {
  create: string[];
  editIssuer: Array<{ id: string; issuer: string }>;
  editUsername: Array<{ id: string; username: string }>;
  editTags: Array<{ id: string; tags: string[] }>;
  editPinned: Array<{ id: string; pinned: boolean }>;
}

interface FakeApi {
  api: ImportApi;
  calls: ApiCalls;
}

// created 由用例决定“服务端实际存下的值”（可模拟 totp-rs 的冒号切分）
const fakeApi = (
  created: (uri: string, index: number) => Partial<Item>,
  failCreateAt?: number,
): FakeApi => {
  const calls: ApiCalls = {
    create: [],
    editIssuer: [],
    editUsername: [],
    editTags: [],
    editPinned: [],
  };

  let index = 0;

  const api: ImportApi = {
    async create(uri: string): Promise<Item> {
      if (failCreateAt === index) {
        index += 1;
        throw new Error("create failed");
      }

      calls.create.push(uri);
      const partial = created(uri, index);
      index += 1;

      return {
        id: `id-${index}`,
        sort: index,
        code: "000000",
        config: { secret: SECRET, period: 30, digits: 6, algorithm: "SHA1" },
        ...partial,
      } as Item;
    },
    async editIssuer(data): Promise<unknown> {
      calls.editIssuer.push(data);

      return null;
    },
    async editUsername(data): Promise<unknown> {
      calls.editUsername.push(data);

      return null;
    },
    async editTags(data): Promise<unknown> {
      calls.editTags.push(data);

      return null;
    },
    async editPinned(data): Promise<unknown> {
      calls.editPinned.push(data);

      return null;
    },
  };

  return { api, calls };
};

describe("backup exporter", () => {
  it("buildExport_skipsMissingSecretAndInvalidItems", async () => {
    const result = await buildExport(
      [
        CACHE_ITEM("GitHub", "alice", SECRET),
        CACHE_ITEM("Missing", "bob", ""),
        CACHE_ITEM("Broken", "carol", "JBSWY3DP1"),
      ],
      {
        password: PASSWORD,
        app: "1.2.0",
        rng: deterministicRng(),
        iterations: 10000,
      },
    );

    expect(result.count).toBe(1);
    expect(result.skipped).toBe(2);
  });

  it("buildExport_outputCanBeAnalyzedBack", async () => {
    const exported = await buildExport(
      [CACHE_ITEM("GitHub", "alice", SECRET)],
      {
        password: PASSWORD,
        app: "1.2.0",
        rng: deterministicRng(),
        iterations: 10000,
      },
    );
    const plan = await analyze(exported.text, PASSWORD, []);

    expect(plan.accepted.length).toBe(1);
    expect(plan.accepted[0].item.issuer).toBe("GitHub");
    expect(plan.envelope.meta.source).toBe("wechat");
  });
});

describe("backup importer analyze", () => {
  it("planUriIssuer_matchesSpec62", () => {
    expect(planUriIssuer("GitHub")).toBe("GitHub");
    expect(planUriIssuer("A:B")).toBe("__mfa__");
    expect(planUriIssuer("")).toBe("__mfa__");
  });

  it("analyze_deduplicatesAgainstLocalAndWithinBatch", async () => {
    const text = await encryptItems([
      ITEM("GitHub", "alice"),
      ITEM("GitHub", "alice"),
    ]);
    const plan = await analyze(text, PASSWORD, [
      CACHE_ITEM("GitHub", "alice", SECRET),
    ]);

    expect(plan.accepted.length).toBe(0);
    expect(plan.duplicates).toBe(2);
  });

  it("analyze_ignoresExistingItemsWithoutSecret", async () => {
    const text = await encryptItems([ITEM("GitHub", "alice")]);
    const plan = await analyze(text, PASSWORD, [
      CACHE_ITEM("GitHub", "alice", ""),
    ]);

    expect(plan.accepted.length).toBe(1);
    expect(plan.duplicates).toBe(0);
  });

  it("analyze_countsInvalidItemsWithoutBlocking", async () => {
    const text = await encryptItems([
      ITEM("GitHub", "alice"),
      ITEM("Broken", "bob", "JBSWY3DP1"),
    ]);
    const plan = await analyze(text, PASSWORD, []);

    expect(plan.accepted.length).toBe(1);
    expect(plan.invalid.length).toBe(1);
    expect(plan.envelopeCount).toBe(2);
  });

  it("analyze_wrongPasswordThrowsEPassword", async () => {
    const text = await encryptItems([ITEM("GitHub", "alice")]);
    let code: string | undefined;

    try {
      await analyze(text, "WrongPassword123", []);
    } catch (e) {
      code = (e as { code?: string }).code;
    }

    expect(code).toBe(BackupErrorCode.E_PASSWORD);
  });
});

describe("backup importer run", () => {
  it("run_plainIssuerCreatesDirectlyWithoutCorrection", async () => {
    const text = await encryptItems([ITEM("GitHub", "alice")]);
    const plan = await analyze(text, PASSWORD, []);
    const { api, calls } = fakeApi(() => ({
      issuer: "GitHub",
      username: "alice",
    }));
    const report = await run(plan, { api });

    expect(report.done).toBe(1);
    expect(report.failed.length).toBe(0);
    expect(calls.create.length).toBe(1);
    expect(calls.editIssuer.length).toBe(0);
  });

  it("run_colonIssuerUsesPlaceholderThenCorrects", async () => {
    const text = await encryptItems([ITEM("A:B", "a:b")]);
    const plan = await analyze(text, PASSWORD, []);

    expect(plan.accepted[0].uri).toContain("__mfa__");

    const { api, calls } = fakeApi(() => ({
      issuer: "__mfa__",
      username: "a:b",
    }));
    const report = await run(plan, { api });

    expect(report.done).toBe(1);
    expect(report.failed.length).toBe(0);
    expect(calls.editIssuer).toEqual([{ id: "id-1", issuer: "A:B" }]);
    expect(calls.editUsername.length).toBe(0);
  });

  it("run_emptyIssuerWithColonUsernameCorrectsIssuerToEmpty", async () => {
    const text = await encryptItems([ITEM("", "a:b")]);
    const plan = await analyze(text, PASSWORD, []);
    const { api, calls } = fakeApi(() => ({
      issuer: "__mfa__",
      username: "a:b",
    }));
    const report = await run(plan, { api });

    expect(report.done).toBe(1);
    expect(calls.editIssuer).toEqual([{ id: "id-1", issuer: "" }]);
  });

  it("run_plainIssuerWithColonUsernameNeedsNoIssuerCorrection", async () => {
    const text = await encryptItems([ITEM("X", "a:b")]);
    const plan = await analyze(text, PASSWORD, []);
    const { api, calls } = fakeApi(() => ({
      issuer: "X",
      username: "a:b",
    }));
    const report = await run(plan, { api });

    expect(report.done).toBe(1);
    expect(calls.editIssuer.length).toBe(0);
    expect(calls.editUsername.length).toBe(0);
  });

  it("run_appliesTagsAndPinned", async () => {
    const item: BackupItem = {
      ...ITEM("GitHub", "alice"),
      tags: ["工作"],
      pinned: true,
    };
    const text = await encryptItems([item]);
    const plan = await analyze(text, PASSWORD, []);
    const { api, calls } = fakeApi(() => ({
      issuer: "GitHub",
      username: "alice",
    }));
    const report = await run(plan, { api });

    expect(report.withTags).toBe(1);
    expect(report.withPinned).toBe(1);
    expect(calls.editTags).toEqual([{ id: "id-1", tags: ["工作"] }]);
    expect(calls.editPinned).toEqual([{ id: "id-1", pinned: true }]);
  });

  it("run_singleFailureDoesNotStopRemainingItems", async () => {
    const text = await encryptItems([
      ITEM("One", "a"),
      ITEM("Two", "b"),
      ITEM("Three", "c"),
    ]);
    const plan = await analyze(text, PASSWORD, []);
    const { api, calls } = fakeApi(
      (_uri, index) => ({
        issuer: `Issuer-${index}`,
        username: `user-${index}`,
      }),
      1,
    );
    const report = await run(plan, { api });

    expect(report.done).toBe(2);
    expect(report.failed.length).toBe(1);
    expect(report.failed[0].stage).toBe("create");
    expect(calls.create.length).toBe(2);
  });

  it("run_cancellationKeepsCreatedItems", async () => {
    const text = await encryptItems([
      ITEM("One", "a"),
      ITEM("Two", "b"),
      ITEM("Three", "c"),
    ]);
    const plan = await analyze(text, PASSWORD, []);
    const { api } = fakeApi(() => ({ issuer: "X", username: "y" }));
    let calls = 0;
    const report = await run(plan, {
      api,
      shouldCancel: () => {
        calls += 1;

        return calls >= 2;
      },
    });

    expect(report.done).toBe(1);
    expect(report.canceled).toBe(true);
    expect(report.notExecuted).toBe(2);
  });

  it("run_correctionFailureIsRecordedWithoutRollback", async () => {
    const text = await encryptItems([ITEM("A:B", "u")]);
    const plan = await analyze(text, PASSWORD, []);
    const api: ImportApi = {
      async create(): Promise<Item> {
        return {
          id: "id-1",
          issuer: "__mfa__",
          username: "u",
        } as Item;
      },
      async editIssuer(): Promise<unknown> {
        throw new Error("edit failed");
      },
      async editUsername(): Promise<unknown> {
        return null;
      },
      async editTags(): Promise<unknown> {
        return null;
      },
      async editPinned(): Promise<unknown> {
        return null;
      },
    };
    const report = await run(plan, { api });

    expect(report.done).toBe(1);
    expect(report.failed.length).toBe(1);
    expect(report.failed[0].stage).toBe("issuer");
  });

  it("run_reportsProgress", async () => {
    const text = await encryptItems([ITEM("One", "a"), ITEM("Two", "b")]);
    const plan = await analyze(text, PASSWORD, []);
    const { api } = fakeApi(() => ({ issuer: "X", username: "y" }));
    const progress: Array<[number, number]> = [];
    await run(plan, {
      api,
      onProgress: (done, total) => progress.push([done, total]),
    });

    expect(progress).toEqual([
      [1, 2],
      [2, 2],
    ]);
  });
});
