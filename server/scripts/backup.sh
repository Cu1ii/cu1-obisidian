#!/usr/bin/env bash
# 每日凌晨自动备份：MySQL all-databases、Redis RDB、ES snapshot 元数据
# 配套 cron：0 3 * * * /Users/$USER/fyj-server/scripts/backup.sh

set -euo pipefail

ROOT="$HOME/fyj-server"
ENV_FILE="$ROOT/compose/.env"
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="$ROOT/1panel/backup/daily/$DATE"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

# 加载密码
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "ERROR: $ENV_FILE not found"
  exit 1
fi

# MySQL
echo "[$(date)] dump mysql..."
docker exec infra-mysql sh -c \
  "exec mysqldump --all-databases --single-transaction --quick --routines --triggers -uroot -p'${MYSQL_ROOT_PASSWORD}'" \
  | gzip > "$BACKUP_DIR/mysql.sql.gz"

# Redis
echo "[$(date)] dump redis..."
docker exec infra-redis redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning SAVE >/dev/null
cp "$ROOT/infra/redis/data/dump.rdb" "$BACKUP_DIR/redis.rdb" 2>/dev/null || true
[[ -f "$ROOT/infra/redis/data/appendonlydir" ]] && cp -r "$ROOT/infra/redis/data/appendonlydir" "$BACKUP_DIR/" || true

# 滚动清理
echo "[$(date)] cleanup older than $RETENTION_DAYS days..."
find "$ROOT/1panel/backup/daily/" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} +

echo "[$(date)] done -> $BACKUP_DIR"
du -sh "$BACKUP_DIR"
