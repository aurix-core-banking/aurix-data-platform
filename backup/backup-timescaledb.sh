#!/usr/bin/env bash
# =============================================================================
# Aurix Platform - Backup TimescaleDB
# pg_dump (formato custom), arquivamento continuo WAL, retencao 30 dias
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${SCRIPT_DIR}/local-backups/timescaledb"

# Configuracao via env
TS_HOST="${TS_HOST:-localhost}"
TS_PORT="${TS_PORT:-5433}"
TS_USER="${TS_USER:-aurix}"
TS_PASSWORD="${TS_PASSWORD:-aurix_dev_password}"
TS_DATABASE="${TS_DATABASE:-aurix_timeseries}"

S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:9000}"
S3_BUCKET="${S3_BUCKET:-aurix-backups-dev}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-minioadmin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-minioadmin}"

RETENTION_DAYS="${RETENTION_DAYS:-30}"
BACKUP_FILE="aurix_timeseries_${TIMESTAMP}.dump"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Inicio do backup TimescaleDB ==="

mkdir -p "${BACKUP_DIR}"

export PGPASSWORD="${TS_PASSWORD}"

# 1. Backup completo com pg_dump (formato custom para restore flexivel)
log "Executando pg_dump (formato custom) do banco ${TS_DATABASE}..."
pg_dump \
    --host="${TS_HOST}" \
    --port="${TS_PORT}" \
    --username="${TS_USER}" \
    --dbname="${TS_DATABASE}" \
    --format=custom \
    --compress=6 \
    --verbose \
    --no-owner \
    --no-privileges \
    --file="${BACKUP_DIR}/${BACKUP_FILE}"

BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_FILE}" | awk '{print $1}')
log "Backup concluido: ${BACKUP_FILE} (${BACKUP_SIZE})"

# 2. Dump adicional no formato SQL puro (para inspecao/human-readable)
log "Gerando dump SQL para inspecao..."
SQL_FILE="aurix_timeseries_${TIMESTAMP}.sql"
pg_dump \
    --host="${TS_HOST}" \
    --port="${TS_PORT}" \
    --username="${TS_USER}" \
    --dbname="${TS_DATABASE}" \
    --format=plain \
    --no-owner \
    --no-privileges \
    --file="${BACKUP_DIR}/${SQL_FILE}"

# 3. Listar hypertables e metadados TimescaleDB
log "Extraindo metadados das hypertables..."
psql \
    --host="${TS_HOST}" \
    --port="${TS_PORT}" \
    --username="${TS_USER}" \
    --dbname="${TS_DATABASE}" \
    --no-align \
    --tuples-only \
    -c "SELECT hypertable_name, num_chunks, compression_enabled
        FROM timescaledb_information.hypertables
        ORDER BY hypertable_name;" \
    > "${BACKUP_DIR}/hypertables_${TIMESTAMP}.csv"

log "Metadados das hypertables exportados"

# 4. Configurar WAL archiving (se habilitado)
if [[ "${ENABLE_WAL_ARCHIVING:-false}" == "true" ]]; then
    log "Configurando arquivamento WAL..."
    WAL_DIR="${SCRIPT_DIR}/wal-archive"
    mkdir -p "${WAL_DIR}"

    psql \
        --host="${TS_HOST}" \
        --port="${TS_PORT}" \
        --username="${TS_USER}" \
        --dbname="${TS_DATABASE}" \
        -c "ALTER SYSTEM SET archive_mode = on;"
    psql \
        --host="${TS_HOST}" \
        --port="${TS_PORT}" \
        --username="${TS_USER}" \
        --dbname="${TS_DATABASE}" \
        -c "ALTER SYSTEM SET archive_command = 'cp %p ${WAL_DIR}/%f';"
    psql \
        --host="${TS_HOST}" \
        --port="${TS_PORT}" \
        --username="${TS_USER}" \
        --dbname="${TS_DATABASE}" \
        -c "SELECT pg_reload_conf();"

    log "WAL archiving configurado (requer restart do PostgreSQL para ativar)"
fi

# 5. Upload para S3/MinIO
log "Upload para S3..."
export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
export AWS_DEFAULT_REGION="us-east-1"

if command -v aws &>/dev/null; then
    aws --endpoint-url "${S3_ENDPOINT}" s3 cp \
        "${BACKUP_DIR}/${BACKUP_FILE}" \
        "s3://${S3_BUCKET}/timescaledb/${TIMESTAMP}/${BACKUP_FILE}"

    aws --endpoint-url "${S3_ENDPOINT}" s3 cp \
        "${BACKUP_DIR}/${SQL_FILE}" \
        "s3://${S3_BUCKET}/timescaledb/${TIMESTAMP}/${SQL_FILE}"

    aws --endpoint-url "${S3_ENDPOINT}" s3 cp \
        "${BACKUP_DIR}/hypertables_${TIMESTAMP}.csv" \
        "s3://${S3_BUCKET}/timescaledb/${TIMESTAMP}/hypertables.csv"

    log "Upload S3 concluido"
else
    log "WARN: aws CLI nao encontrado, backup mantido localmente"
fi

# 6. Limpeza de backups antigos
log "Limpando backups com mais de ${RETENTION_DAYS} dias..."
find "${BACKUP_DIR}" -name "aurix_timeseries_*.dump" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "aurix_timeseries_*.sql" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "hypertables_*.csv" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true

unset PGPASSWORD

log "=== Backup TimescaleDB concluido ==="
