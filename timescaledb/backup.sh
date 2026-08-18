#!/usr/bin/env bash
# Snapshot programado do TimescaleDB via pg_dump (dump lógico compactado).
#
# Uso:
#   ./timescaledb/backup.sh
set -euo pipefail

TIMESCALEDB_CONTAINER="${TIMESCALEDB_CONTAINER:-aurix-timescaledb}"
TIMESCALEDB_DB="${TIMESCALEDB_DB:-aurix_timeseries}"
TIMESCALEDB_USER="${TIMESCALEDB_USER:-aurix}"
TIMESCALEDB_PASSWORD="${TIMESCALEDB_PASSWORD:-aurix_dev_password}"

DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backup/timescaledb"
mkdir -p "${DATA_DIR}"
ARQUIVO="${DATA_DIR}/timescaledb_$(date +%Y%m%d-%H%M%S).dump"

echo "==> Snapshot do TimescaleDB (${TIMESCALEDB_DB}) -> ${ARQUIVO}"
PGPASSWORD="${TIMESCALEDB_PASSWORD}" docker exec "${TIMESCALEDB_CONTAINER}" \
  pg_dump -U "${TIMESCALEDB_USER}" -d "${TIMESCALEDB_DB}" -Fc --no-owner \
  > "${ARQUIVO}"

# Rotação: mantém apenas os 7 snapshots mais recentes
echo "==> Removendo snapshots antigos (mantendo os 7 mais recentes)"
ls -1t "${DATA_DIR}"/*.dump 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "==> Snapshot concluído:"
ls -lh "${ARQUIVO}"
