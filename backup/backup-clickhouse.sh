#!/usr/bin/env bash
# =============================================================================
# Aurix Platform - Backup ClickHouse
# Exporta tabelas do sistema, executa clickhouse-backup e upload para S3/MinIO
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PREFIX="clickhouse/${TIMESTAMP}"

# Configuracao via env
CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-aurix}"
CH_PASSWORD="${CH_PASSWORD:-aurix_dev_password}"
CH_DATABASE="${CH_DATABASE:-aurix_analytics}"

S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:9000}"
S3_BUCKET="${S3_BUCKET:-aurix-backups-dev}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-minioadmin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-minioadmin}"

RETENTION_DAYS="${RETENTION_DAYS:-30}"
BACKUP_NAME="clickhouse_full_${TIMESTAMP}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Inicio do backup ClickHouse ==="

# 1. Exportar metadados das tabelas do sistema
log "Exportando metadados do sistema..."
METADATA_DIR="${SCRIPT_DIR}/metadata"
mkdir -p "${METADATA_DIR}"

clickhouse-client \
    --host "${CH_HOST}" \
    --port "${CH_PORT}" \
    --user "${CH_USER}" \
    --password "${CH_PASSWORD}" \
    --database "${CH_DATABASE}" \
    --query "SELECT name, engine, partition_key, total_rows, total_bytes
             FROM system.tables
             WHERE database = '${CH_DATABASE}'
             ORDER BY name" \
    --format PrettyCSV > "${METADATA_DIR}/tables_${TIMESTAMP}.csv"

clickhouse-client \
    --host "${CH_HOST}" \
    --port "${CH_PORT}" \
    --user "${CH_USER}" \
    --password "${CH_PASSWORD}" \
    --query "SELECT * FROM system.parts
             WHERE active AND database = '${CH_DATABASE}'
             ORDER BY table, partition" \
    --format PrettyCSV > "${METADATA_DIR}/parts_${TIMESTAMP}.csv"

log "Metadados exportados para ${METADATA_DIR}"

# 2. Executar clickhouse-backup (se disponivel)
if command -v clickhouse-backup &>/dev/null; then
    log "Executando clickhouse-backup..."
    clickhouse-backup create "${BACKUP_NAME}"
    log "Backup local criado: ${BACKUP_NAME}"

    # Upload para S3/MinIO
    log "Configurando S3 para upload..."
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
    export AWS_DEFAULT_REGION="us-east-1"

    if command -v aws &>/dev/null; then
        log "Upload para S3: s3://${S3_BUCKET}/${BACKUP_PREFIX}/"
        aws --endpoint-url "${S3_ENDPOINT}" s3 cp \
            "${HOME}/clickhouse-backup/${BACKUP_NAME}" \
            "s3://${S3_BUCKET}/${BACKUP_PREFIX}/${BACKUP_NAME}" \
            --recursive
        log "Upload concluido"
    else
        log "WARN: aws CLI nao encontrado, copiando backup localmente"
        LOCAL_BACKUP_DIR="${SCRIPT_DIR}/local-backups/${BACKUP_NAME}"
        mkdir -p "${LOCAL_BACKUP_DIR}"
        cp -r "${HOME}/clickhouse-backup/${BACKUP_NAME}/"* "${LOCAL_BACKUP_DIR}/"
    fi
else
    log "WARN: clickhouse-backup nao encontrado, usando exportacao manual"

    # Exportacao manual via INSERT INTO OUTFILE
    BACKUP_DIR="${SCRIPT_DIR}/local-backups/${BACKUP_NAME}"
    mkdir -p "${BACKUP_DIR}"

    TABLES=$(clickhouse-client \
        --host "${CH_HOST}" \
        --port "${CH_PORT}" \
        --user "${CH_USER}" \
        --password "${CH_PASSWORD}" \
        --database "${CH_DATABASE}" \
        --query "SELECT name FROM system.tables WHERE database = '${CH_DATABASE}' AND engine != 'View'" \
        --format TSVRaw)

    for TABLE in ${TABLES}; do
        log "Exportando tabela: ${TABLE}"
        clickhouse-client \
            --host "${CH_HOST}" \
            --port "${CH_PORT}" \
            --user "${CH_USER}" \
            --password "${CH_PASSWORD}" \
            --database "${CH_DATABASE}" \
            --query "SELECT * FROM ${TABLE} FORMAT TabSeparatedWithNamesAndTypes" \
            > "${BACKUP_DIR}/${TABLE}.tsv"
    done

    log "Exportacao manual concluida em ${BACKUP_DIR}"
fi

# 3. Limpeza de backups antigos no S3
log "Verificando retencao (ultimos ${RETENTION_DAYS} dias)..."
if command -v aws &>/dev/null; then
    CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" +%Y%m%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y%m%d)
    aws --endpoint-url "${S3_ENDPOINT}" s3 ls "s3://${S3_BUCKET}/clickhouse/" | while read -r LINE; do
        DIR_DATE=$(echo "${LINE}" | awk '{print $2}' | tr -d '/')
        if [[ "${DIR_DATE}" < "${CUTOFF_DATE}" && -n "${DIR_DATE}" ]]; then
            log "Removendo backup antigo: ${DIR_DATE}"
            aws --endpoint-url "${S3_ENDPOINT}" s3 rm \
                "s3://${S3_BUCKET}/clickhouse/${DIR_DATE}/" --recursive
        fi
    done
fi

log "=== Backup ClickHouse concluido ==="
