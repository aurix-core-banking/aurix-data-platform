#!/usr/bin/env bash
# Restore do ClickHouse a partir de um backup nativo.
#
# Uso:
#   ./clickhouse/restore.sh [rotulo]
set -euo pipefail

CLICKHOUSE_CONTAINER="${CLICKHOUSE_CONTAINER:-aurix-clickhouse}"
CLICKHOUSE_DB="${CLICKHOUSE_DB:-aurix_analytics}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-aurix}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-aurix_dev_password}"

ROTULO="${1:?Informe o rótulo do backup, ex.: 20260203-100000}"
ORIGEM="/var/lib/clickhouse/backups/backup_${ROTULO}"

echo "==> Listando backups disponíveis:"
docker exec "${CLICKHOUSE_CONTAINER}" \
  clickhouse-client --user "${CLICKHOUSE_USER}" --password "${CLICKHOUSE_PASSWORD}" \
  --query "SELECT name, status FROM system.backups"

echo "==> Restaurando ${CLICKHOUSE_DB} a partir de ${ORIGEM}"
docker exec "${CLICKHOUSE_CONTAINER}" \
  clickhouse-client \
    --host localhost \
    --user "${CLICKHOUSE_USER}" \
    --password "${CLICKHOUSE_PASSWORD}" \
    --query "RESTORE DATABASE ${CLICKHOUSE_DB} FROM File('${ORIGEM}')"

echo "==> Restore concluído."
