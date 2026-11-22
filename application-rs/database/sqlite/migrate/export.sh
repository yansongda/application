#!/usr/bin/env bash
# 从 TiDB 导出 account / tool 两套 schema 的数据为 TSV，供 import.py 消费。
#
# 只读操作，不会修改源库。凭据一律通过环境变量注入，不要写进脚本或提交到仓库。
#
# 必需环境变量：TIDB_HOST / TIDB_USER / TIDB_PASS
# 可选环境变量：TIDB_PORT（默认 4000）、TIDB_SSL_MODE（默认 REQUIRED）、OUT_DIR（默认 ./dump）
#
# 用法：TIDB_HOST=xxx TIDB_USER=xxx TIDB_PASS=xxx ./export.sh

set -euo pipefail

: "${TIDB_HOST:?请设置 TIDB_HOST}"
: "${TIDB_USER:?请设置 TIDB_USER}"
: "${TIDB_PASS:?请设置 TIDB_PASS}"

TIDB_PORT="${TIDB_PORT:-4000}"
TIDB_SSL_MODE="${TIDB_SSL_MODE:-REQUIRED}"
OUT_DIR="${OUT_DIR:-./dump}"

CLIENT_ARGS=(
  --host="$TIDB_HOST"
  --port="$TIDB_PORT"
  --user="$TIDB_USER"
  --password="$TIDB_PASS"
  --ssl-mode="$TIDB_SSL_MODE"
  --default-character-set=utf8mb4
  --batch
  --skip-column-names
  # TiDB 会话时区默认是 UTC，这里显式固定，避免依赖服务器配置
  --init-command="SET time_zone = '+00:00'"
)

# 表清单：schema:table:columns（列顺序与 import.py 一一对应，不要随意调整）
TABLES=(
  "account:user:id,phone,config,created_at,updated_at"
  "account:third_user:id,user_id,platform,third_id,config,created_at,updated_at"
  "account:third_config:id,platform,third_id,config,created_at,updated_at"
  "account:access_token:id,user_id,platform,third_id,access_token,data,expired_at,created_at,updated_at"
  "account:refresh_token:id,access_token_id,refresh_token,expired_at,created_at,updated_at"
  "tool:short_url:id,short,url,visit,created_at,updated_at"
  "tool:totp:id,user_id,username,issuer,config,created_at,updated_at,sort"
)

mkdir -p "$OUT_DIR/schema"

echo "==> 导出表结构快照（迁移后用于比对，不参与导入）"
for entry in "${TABLES[@]}"; do
  IFS=":" read -r schema table _ <<<"$entry"
  mysql "${CLIENT_ARGS[@]}" -e "SHOW CREATE TABLE \`$schema\`.\`$table\`" \
    >"$OUT_DIR/schema/$schema.$table.sql"
done

echo "==> 导出数据（按 created_at, id 排序，便于导入时按时间顺序重新编号）"
for entry in "${TABLES[@]}"; do
  IFS=":" read -r schema table columns <<<"$entry"
  echo "    $schema.$table"
  mysql "${CLIENT_ARGS[@]}" -e \
    "select $columns from \`$schema\`.\`$table\` order by created_at, id" \
    >"$OUT_DIR/$schema.$table.tsv"
done

echo "==> 完成，输出目录：$OUT_DIR"
wc -l "$OUT_DIR"/*.tsv
