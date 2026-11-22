#!/usr/bin/env python3
"""把 export.sh 导出的 TSV 导入到空的 SQLite 库。

只用 Python 3 标准库，不需要 pip 安装任何依赖。

三个关键处理：

1. **主键重新编号**：TiDB 侧主键是 `AUTO_RANDOM` 生成的 64 位无符号数，约一半超过
   `i64::MAX`，SQLite 的 `INTEGER` 存不下。这里按导出的 `(created_at, id)` 顺序把每张表
   重新编号为 `1..N`，并同步改写所有外键（`user_id` / `access_token_id`）。
   因为 `totp.user_id` 在 tool.db、`user.id` 在 account.db，跨库无法用 SQL 关联，
   映射必须在进程内维护。

2. **时区**：export.sh 已 `SET time_zone = '+00:00'`，所以读到的墙钟时间是 UTC。
   这里按 UTC 解释后转换为 `+08:00` 的 RFC3339 文本，与后端 `Local::now()` 的写入格式一致。

3. **JSON 列**：原样作为 TEXT 写入，不做 parse 再序列化，避免键顺序/数字精度漂移；
   但会先 `json.loads` 校验一遍，坏数据在导入阶段就报错。

用法：
    python3 import.py --dump-dir ./dump \
        --account-db /www/data/account.db \
        --tool-db /www/data/tool.db
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

LOCAL_TZ = timezone(timedelta(hours=8))

# 每张表：表名、(列顺序，必须与 export.sh 一致)、时间列、外键列 -> 引用的 id 映射名
ACCOUNT_TABLES = [
    ("user", ["id", "phone", "config", "created_at", "updated_at"], ["created_at", "updated_at"], {}),
    (
        "third_user",
        ["id", "user_id", "platform", "third_id", "config", "created_at", "updated_at"],
        ["created_at", "updated_at"],
        {"user_id": "user"},
    ),
    (
        "third_config",
        ["id", "platform", "third_id", "config", "created_at", "updated_at"],
        ["created_at", "updated_at"],
        {},
    ),
    (
        "access_token",
        [
            "id",
            "user_id",
            "platform",
            "third_id",
            "access_token",
            "data",
            "expired_at",
            "created_at",
            "updated_at",
        ],
        ["expired_at", "created_at", "updated_at"],
        {"user_id": "user"},
    ),
    (
        "refresh_token",
        ["id", "access_token_id", "refresh_token", "expired_at", "created_at", "updated_at"],
        ["expired_at", "created_at", "updated_at"],
        {"access_token_id": "access_token"},
    ),
]

TOOL_TABLES = [
    ("short_url", ["id", "short", "url", "visit", "created_at", "updated_at"], ["created_at", "updated_at"], {}),
    (
        "totp",
        ["id", "user_id", "username", "issuer", "config", "created_at", "updated_at", "sort"],
        ["created_at", "updated_at"],
        {"user_id": "user"},
    ),
]

JSON_COLUMNS = {"config", "data"}

# MySQL `--batch` 输出里的转义字符
_ESCAPES = {"0": "\0", "t": "\t", "n": "\n", "r": "\r", "\\": "\\", "b": "\b"}


def unescape(field: str) -> str:
    if "\\" not in field:
        return field

    out = []
    i = 0
    while i < len(field):
        ch = field[i]
        if ch == "\\" and i + 1 < len(field):
            out.append(_ESCAPES.get(field[i + 1], field[i + 1]))
            i += 2
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def read_tsv(path: Path, columns: list[str]) -> list[dict[str, object]]:
    """读取 mysql --batch 的 TSV；`\\N` 表示 NULL。"""
    rows: list[dict[str, object]] = []

    with path.open(encoding="utf-8", newline="\n") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.rstrip("\n")
            if not line:
                continue

            fields = line.split("\t")
            if len(fields) != len(columns):
                raise SystemExit(f"{path}:{lineno} 列数不匹配：期望 {len(columns)}，实际 {len(fields)}")

            row: dict[str, object] = {}
            for column, field in zip(columns, fields):
                row[column] = None if field == "\\N" else unescape(field)
            rows.append(row)

    return rows


def ts_to_local(value: str) -> str:
    """`2026-11-09 13:23:29`（UTC）→ `2026-11-09T21:23:29+08:00`"""
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M:%S.%f"):
        try:
            dt = datetime.strptime(value, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue

        return dt.astimezone(LOCAL_TZ).isoformat()

    raise SystemExit(f"无法解析时间值: {value!r}")


def build_id_map(rows: list[dict[str, object]]) -> dict[int, int]:
    """按导出顺序（已是 created_at, id 升序）重新编号为 1..N。"""
    id_map: dict[int, int] = {}
    for new_id, row in enumerate(rows, start=1):
        id_map[int(row["id"])] = new_id  # type: ignore[arg-type]

    return id_map


def convert_rows(
    rows: list[dict[str, object]],
    columns: list[str],
    ts_columns: list[str],
    fks: dict[str, str],
    id_maps: dict[str, dict[int, int]],
    table: str,
) -> list[tuple[object, ...]]:
    converted: list[tuple[object, ...]] = []

    for new_id, row in enumerate(rows, start=1):
        values: list[object] = []
        for column in columns:
            value = row[column]

            if column == "id":
                values.append(new_id)
                continue

            if value is None:
                values.append(None)
                continue

            assert isinstance(value, str)

            if column in ts_columns:
                values.append(ts_to_local(value))
                continue

            if column in fks:
                id_map = id_maps[fks[column]]
                try:
                    values.append(id_map[int(value)])
                except KeyError as e:
                    raise SystemExit(f"{table}.{column} 引用了不存在的 id: {value}（原值）") from e
                continue

            if column in JSON_COLUMNS:
                try:
                    json.loads(value)
                except json.JSONDecodeError as e:
                    raise SystemExit(f"{table}.{column} 不是合法 JSON: {e}") from e

            values.append(value)

        converted.append(tuple(values))

    return converted


def load(conn: sqlite3.Connection, table: str, columns: list[str], rows: list[tuple[object, ...]]) -> None:
    if not rows:
        print(f"    {table}: 0 行")
        return

    placeholders = ", ".join("?" * len(columns))
    sql = f"insert into {table} ({', '.join(columns)}) values ({placeholders})"
    conn.executemany(sql, rows)
    print(f"    {table}: {len(rows)} 行")


def main() -> int:
    parser = argparse.ArgumentParser(description="TiDB TSV dump → SQLite")
    parser.add_argument("--dump-dir", default="./dump", type=Path)
    parser.add_argument("--account-db", required=True, type=Path)
    parser.add_argument("--tool-db", required=True, type=Path)
    args = parser.parse_args()

    for db in (args.account_db, args.tool_db):
        if not db.exists():
            return _fail(f"目标库不存在：{db}（请先用 00-init.sql 建库）")

    dumps = args.dump_dir
    missing = [
        f"{schema}.{table}"
        for schema, tables in (("account", ACCOUNT_TABLES), ("tool", TOOL_TABLES))
        for table, *_ in tables
        if not (dumps / f"{schema}.{table}.tsv").exists()
    ]
    if missing:
        return _fail(f"缺少导出文件：{', '.join(missing)}（先运行 export.sh）")

    print("==> 读取导出文件")
    account_data = {table: read_tsv(dumps / f"account.{table}.tsv", columns) for table, columns, *_ in ACCOUNT_TABLES}
    tool_data = {table: read_tsv(dumps / f"tool.{table}.tsv", columns) for table, columns, *_ in TOOL_TABLES}

    print("==> 构建 id 映射（跨 account/tool 共用）")
    id_maps = {
        "user": build_id_map(account_data["user"]),
        "access_token": build_id_map(account_data["access_token"]),
    }

    print("==> 写入 account.db")
    account_conn = sqlite3.connect(args.account_db)
    try:
        for table, columns, ts_columns, fks in ACCOUNT_TABLES:
            rows = convert_rows(account_data[table], columns, ts_columns, fks, id_maps, table)
            load(account_conn, table, columns, rows)
        account_conn.commit()
    finally:
        account_conn.close()

    print("==> 写入 tool.db")
    tool_conn = sqlite3.connect(args.tool_db)
    try:
        for table, columns, ts_columns, fks in TOOL_TABLES:
            rows = convert_rows(tool_data[table], columns, ts_columns, fks, id_maps, table)
            load(tool_conn, table, columns, rows)
        tool_conn.commit()
    finally:
        tool_conn.close()

    print("==> 完成。接下来请运行 verify.py 做一致性校验")

    return 0


def _fail(message: str) -> int:
    print(f"错误：{message}", file=sys.stderr)

    return 1


if __name__ == "__main__":
    sys.exit(main())
