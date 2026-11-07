/**
 * 时间步 / 剩余秒 / 进度 / 恒定时间比较。
 * 参照点与 t0≠0 负值归一化用例逐字对齐 ohos-otp 的 TimeStep.test.ets。
 */
import { describe, expect, it } from "bun:test";
import {
  constantTimeEquals,
  progress,
  remainingSec,
  step,
} from "../../src/otp/internal/time-step";
import { expectCode } from "./helpers";

describe("time-step", () => {
  it("step_reference", () => {
    expect(step(59000, 0, 30)).toBe(1);
    expect(step(60000, 0, 30)).toBe(2);
    expect(step(31000, 1, 30)).toBe(1);
    expect(step(20000000000 * 1000, 0, 30)).toBe(666666666);
  });

  it("remaining_reference", () => {
    expect(remainingSec(59000, 0, 30)).toBe(1);
    expect(remainingSec(60000, 0, 30)).toBe(30);
    expect(remainingSec(1000, 0, 30)).toBe(29);
    expect(remainingSec(45000, 0, 45)).toBe(45);
  });

  it("remaining_t0_nonZeroAndNegativeNormalization", () => {
    expect(remainingSec(31000, 1, 30)).toBe(30);
    // ((1-5)%30+30)%30=26 → 30-26=4
    expect(remainingSec(1000, 5, 30)).toBe(4);
  });

  it("progress_reference", () => {
    expect(progress(15000, 0, 30)).toBe(0.5);
    expect(progress(1000, 0, 30)).toBeCloseTo(1 / 30, 10);
    expect(progress(31000, 1, 30)).toBe(0);
  });

  it("step_invalidTimestamp_throws", () => {
    expectCode(() => step(0, 0, 30), "INVALID_TIMESTAMP");
    expectCode(() => step(-1, 0, 30), "INVALID_TIMESTAMP");
    expectCode(() => step(Number.NaN, 0, 30), "INVALID_TIMESTAMP");
    expectCode(
      () => step(Number.POSITIVE_INFINITY, 0, 30),
      "INVALID_TIMESTAMP",
    );
  });

  it("step_invalidT0_throws", () => {
    expectCode(() => step(59000, -1, 30), "INVALID_T0");
    expectCode(() => step(59000, 1.5, 30), "INVALID_T0");
  });

  it("step_invalidPeriod_throws", () => {
    expectCode(() => step(59000, 0, 0), "INVALID_PERIOD");
    expectCode(() => step(59000, 0, -30), "INVALID_PERIOD");
  });

  it("constantTimeEquals", () => {
    expect(constantTimeEquals("287082", "287082")).toBe(true);
    expect(constantTimeEquals("287082", "287083")).toBe(false);
    expect(constantTimeEquals("287082", "28708")).toBe(false);
    expect(constantTimeEquals("", "")).toBe(true);
  });
});
