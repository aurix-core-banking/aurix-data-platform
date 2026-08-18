#!/usr/bin/env bash
# Backup automático do ClickHouse (tabelas + metadados).
#
# Usa o comando nativo BACKUP do ClickHouse (23.8+) via clickhouse-client.
# O destino `/var/lib/clickhouse/backups` é um bind mount de `backup/clickhouse`
# definido no docker-compose.yml.
#
# Uso:
#   ./clickhouse/backup.sh [rotulo]
set -euo pipefail

CLICKHOUSE_CONTAINER="${CLICKHOUSE_CONTAINER:-aurix-clickhouse}"
CLICKHOUSE_DB="${CLICKHOUSE_DB:-aurix_analytics}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-aurix}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-aurix_dev_password}"

ROTULO="${1:-$(date +%Y%m%d-%H%M%S)}"
DESTINO="/var/lib/clickhouse/backups/backup_${ROTULO}"

echo "==> Iniciando backup do ClickHouse (${CLICKHOUSE_DB}) em ${DESTINO}"
docker exec "${CLICKHOUSE_CONTAINER}" \
  clickhouse-client \
    --host localhost \
    --user "${CLICKHOUSE_USER}" \
    --password "${CLICKHOUSE_PASSWORD}" \
    --query "BACKUP DATABASE ${CLICKHOUSE_DB} TO File('${DESTINO}')"

echo "==> Backup concluído. Verifique a lista de backups:"
docker exec "${CLICKHOUSE_CONTAINER}" \
  clickhouse-client --user "${CLICKHOUSE_USER}" --password "${CLICKHOUSE_PASSWORD}" \
  --query "SELECT name, status FROM system.backups ORDER BY name DESC LIMIT 5"
