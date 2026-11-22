#!/usr/bin/env python3
"""校验 TiDB → SQLite 迁移结果是否与导出一致。

检查项：
  1. 行数：与 TSV 导出行数逐表对齐
  2. JSON 列：全部通过 `json_valid`
  3. 外键完整性：`third_user` / `access_token` / `refresh_token` / `totp` 的引用都能命中
  4. 时间列：所有 timestamp 的**绝对时刻**与导出完全一致（只允许文本格式变化）
  5. `AUTOINCREMENT` 序列：`sqlite_sequence.seq` 与 `max(id)` 一致，避免新插入撞号
  6. 关键唯一索引存在

用法：
    python3 verify.py --dump-dir ./dump \
        --account-db /www/data/account.db \
        --tool-db /www/data/tool.db
"""

from __future__ import annotations

import argparse
import importlib.util
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("migrate_import", Path(__file__).with_name("import.py"))
assert _SPEC is not None and _SPEC.loader is not None
migrate = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(migrate)

ACCOUNT_TABLES = migrate.ACCOUNT_TABLES
TOOL_TABLES = migrate.TOOL_TABLES

EXPECTED_UNIQUE_INDEXES = {
    "account": [
        "uk_third_user_platform_third_id",
        "uk_third_config_platform_third_id",
        "uk_account_access_token",
        "uk_account_access_token_id",
        "uk_account_refresh_token",
    ],
    "tool": ["uk_tool_short"],
}

failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    suffix = f" — {detail}" if detail else ""
    print(f"[{'PASS' if ok else 'FAIL'}] {name}{suffix}")
    if not ok:
        failures.append(name)


def normalize(value: str) -> str:
    return datetime.fromisoformat(value).astimezone(timezone.utc).isoformat()


def table_columns(specs) -> dict[str, tuple[list[str], list[str]]]:
    return {table: (columns, ts) for table, columns, ts, _ in specs}


def main() -> int:
    parser = argparse.ArgumentParser(description="校验 SQLite 迁移结果")
    parser.add_argument("--dump-dir", default="./dump", type=Path)
    parser.add_argument("--account-db", required=True, type=Path)
    parser.add_argument("--tool-db", required=True, type=Path)
    args = parser.parse_args()

    dumps: Path = args.dump_dir
    account_conn = sqlite3.connect(args.account_db)
    tool_conn = sqlite3.connect(args.tool_db)

    groups = [
        ("account", account_conn, ACCOUNT_TABLES),
        ("tool", tool_conn, TOOL_TABLES),
    ]

    print("==> 1/6 行数")
    for schema, conn, specs in groups:
        for table, columns, _ts, _fks in specs:
            dumped = migrate.read_tsv(dumps / f"{schema}.{table}.tsv", columns)
            actual = conn.execute(f"select count(*) from {table}").fetchone()[0]
            check(f"{schema}.{table} 行数", len(dumped) == actual, f"dump={len(dumped)} sqlite={actual}")

    print("==> 2/6 JSON 合法性")
    for schema, conn, specs in groups:
        for table, columns, _ts, _fks in specs:
            for column in sorted(set(columns) & migrate.JSON_COLUMNS):
                bad = conn.execute(
                    f"select count(*) from {table} where {column} is not null and json_valid({column}) = 0"
                ).fetchone()[0]
                check(f"{schema}.{table}.{column} json_valid", bad == 0, f"非法 {bad} 行")

    print("==> 3/6 外键完整性")
    orphan_checks = [
        (account_conn, "third_user.user_id", "select count(*) from third_user t left join user u on u.id = t.user_id where u.id is null"),
        (account_conn, "access_token.user_id", "select count(*) from access_token t left join user u on u.id = t.user_id where u.id is null"),
        (
            account_conn,
            "refresh_token.access_token_id",
            "select count(*) from refresh_token t left join access_token a on a.id = t.access_token_id where a.id is null",
        ),
    ]
    for conn, label, sql in orphan_checks:
        count = conn.execute(sql).fetchone()[0]
        check(f"{label} 无孤儿", count == 0, f"孤儿 {count} 行")

    user_ids = {row[0] for row in account_conn.execute("select id from user")}
    totp_user_ids = {row[0] for row in tool_conn.execute("select distinct user_id from totp")}
    missing = totp_user_ids - user_ids
    check("tool.totp.user_id 均能命中 account.user", not missing, f"缺失 {sorted(missing)}")

    print("==> 4/6 时间列绝对时刻")
    for schema, conn, specs in groups:
        for table, columns, ts_columns, _fks in specs:
            dumped = migrate.read_tsv(dumps / f"{schema}.{table}.tsv", columns)
            for column in ts_columns:
                expected = sorted(normalize(migrate.ts_to_local(v)) for v in (row[column] for row in dumped) if v)
                actual = sorted(
                    normalize(v)
                    for (v,) in conn.execute(f"select {column} from {table} where {column} is not null")
                )
                check(f"{schema}.{table}.{column} 时刻一致", expected == actual, f"{len(expected)} 个值")

    print("==> 5/6 AUTOINCREMENT 序列")
    for schema, conn, specs in groups:
        for table, _columns, _ts, _fks in specs:
            max_id = conn.execute(f"select coalesce(max(id), 0) from {table}").fetchone()[0]
            row = conn.execute("select seq from sqlite_sequence where name = ?", (table,)).fetchone()
            seq = row[0] if row else 0
            check(f"{schema}.{table} seq >= max(id)", seq >= max_id, f"seq={seq} max_id={max_id}")

    print("==> 6/6 唯一索引")
    for schema, conn, _specs in groups:
        names = {row[0] for row in conn.execute("select name from sqlite_master where type = 'index'")}
        for index in EXPECTED_UNIQUE_INDEXES[schema]:
            check(f"{schema} 索引 {index}", index in names)

    account_conn.close()
    tool_conn.close()

    print()
    if failures:
        print(f"校验未通过，共 {len(failures)} 项失败：")
        for name in failures:
            print(f"  - {name}")

        return 1

    print("全部校验通过")

    return 0


if __name__ == "__main__":
    sys.exit(main())
