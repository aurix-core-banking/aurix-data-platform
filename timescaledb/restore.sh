#!/usr/bin/env bash
# Restore do TimescaleDB a partir de um dump lógico.
#
# Uso:
#   ./timescaledb/restore.sh [arquivo.dump]
set -euo pipefail

TIMESCALEDB_CONTAINER="${TIMESCALEDB_CONTAINER:-aurix-timescaledb}"
TIMESCALEDB_DB="${TIMESCALEDB_DB:-aurix_timeseries}"
TIMESCALEDB_USER="${TIMESCALEDB_USER:-aurix}"
TIMESCALEDB_PASSWORD="${TIMESCALEDB_PASSWORD:-aurix_dev_password}"

DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backup/timescaledb"

ARQUIVO="${1:-$(ls -1t "${DATA_DIR}"/*.dump 2>/dev/null | head -1)}"
if [[ -z "${ARQUIVO}" || ! -f "${ARQUIVO}" ]]; then
  echo "ERRO: nenhum dump encontrado em ${DATA_DIR}." >&2
  exit 1
fi

echo "==> Restaurando ${ARQUIVO} em ${TIMESCALEDB_DB}"
# O dump vai via stdin (docker exec -i) para o pg_restore dentro do container.
PGPASSWORD="${TIMESCALEDB_PASSWORD}" docker exec -i "${TIMESCALEDB_CONTAINER}" \
  pg_restore -U "${TIMESCALEDB_USER}" -d "${TIMESCALEDB_DB}" \
  --no-owner --clean --if-exists < "${ARQUIVO}"

echo "==> Restore concluído."
