#!/usr/bin/env bash
# =============================================================================
# Aurix Platform - Restore Orquestrado
# Restaura ClickHouse, TimescaleDB, Elasticsearch e Kafka com health checks
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="${1:-$(date +%Y%m%d_%H%M%S)}"

# Configuracao via env
CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-aurix}"
CH_PASSWORD="${CH_PASSWORD:-aurix_dev_password}"
CH_DATABASE="${CH_DATABASE:-aurix_analytics}"

TS_HOST="${TS_HOST:-localhost}"
TS_PORT="${TS_PORT:-5433}"
TS_USER="${TS_USER:-aurix}"
TS_PASSWORD="${TS_PASSWORD:-aurix_dev_password}"
TS_DATABASE="${TS_DATABASE:-aurix_timeseries}"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_PROTOCOL="${ES_PROTOCOL:-http}"
ES_SECURITY="${ES_SECURITY:-false}"

KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"

S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:9000}"
S3_BUCKET="${S3_BUCKET:-aurix-backups-dev}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-minioadmin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-minioadmin}"

RESTORE_DIR="${SCRIPT_DIR}/restore-staging/${TIMESTAMP}"
ERRORS=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

health_check() {
    local SERVICE=$1
    local HOST=$2
    local PORT=$3
    local MAX_RETRIES=30
    local RETRY=0

    log "Health check: ${SERVICE} (${HOST}:${PORT})"
    while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
        if nc -z "${HOST}" "${PORT}" 2>/dev/null; then
            log "  ${SERVICE} esta respondendo"
            return 0
        fi
        RETRY=$((RETRY + 1))
        sleep 2
    done

    log "  ERRO: ${SERVICE} nao respondeu apos ${MAX_RETRIES} tentativas"
    return 1
}

log "============================================="
log "  Aurix Platform - Restore Orquestrado"
log "  Timestamp: ${TIMESTAMP}"
log "============================================="

mkdir -p "${RESTORE_DIR}"

# Pre-flight: verificar conectividade com todos os servicos
log "--- Verificando conectividade ---"
health_check "ClickHouse" "${CH_HOST}" "${CH_PORT}" || true
health_check "TimescaleDB" "${TS_HOST}" "${TS_PORT}" || true
health_check "Elasticsearch" "${ES_HOST}" "${ES_PORT}" || true
health_check "Kafka" "${KAFKA_BOOTSTRAP%%:*}" "${KAFKA_BOOTSTRAP##*:}" || true

# ===========================================================================
# 1. RESTORE TIMESCALEDB
# ===========================================================================
log ""
log "=== Restaurando TimescaleDB ==="
export PGPASSWORD="${TS_PASSWORD}"

DUMP_FILE=$(find "${RESTORE_DIR}/../" -path "*/timescaledb/*${TIMESTAMP}*.dump" 2>/dev/null | head -1)

if [[ -n "${DUMP_FILE}" && -f "${DUMP_FILE}" ]]; then
    log "Restaurando de: ${DUMP_FILE}"

    # Verificar integridade do dump
    log "Verificando integridade do dump..."
    pg_restore --list "${DUMP_FILE}" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log "  Dump invalido, abortando restore TimescaleDB"
        ERRORS+=("timescaledb_restore_invalid_dump")
    else
        # Drop e recriar banco (cuidado em producao!)
        log "Restaurando banco ${TS_DATABASE}..."
        pg_restore \
            --host="${TS_HOST}" \
            --port="${TS_PORT}" \
            --username="${TS_USER}" \
            --dbname="${TS_DATABASE}" \
            --clean \
            --if-exists \
            --no-owner \
            --no-privileges \
            --verbose \
            "${DUMP_FILE}" 2>&1 | tail -5

        log "TimescaleDB restaurado com sucesso"
    fi
else
    log "WARN: Nenhum dump TimescaleDB encontrado para ${TIMESTAMP}"
    ERRORS+=("timescaledb_no_dump_found")
fi

unset PGPASSWORD

# ===========================================================================
# 2. RESTORE ELASTICSEARCH
# ===========================================================================
log ""
log "=== Restaurando Elasticsearch ==="

if [[ "${ES_SECURITY}" == "true" ]]; then
    ES_URL="${ES_PROTOCOL}://${ES_USER}:${ES_PASSWORD}@${ES_HOST}:${ES_PORT}"
else
    ES_URL="${ES_PROTOCOL}://${ES_HOST}:${ES_PORT}"
fi

# Verificar snapshots disponiveis
SNAPSHOTS=$(curl -s "${ES_URL}/_snapshot/aurix-backups/_all" 2>/dev/null || echo "{}")
SNAPSHOT_COUNT=$(echo "${SNAPSHOTS}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('snapshots',[])))" 2>/dev/null || echo "0")

if [[ "${SNAPSHOT_COUNT}" -gt 0 ]]; then
    LATEST_SNAPSHOT=$(echo "${SNAPSHOTS}" | python3 -c "
import sys, json
snaps = json.load(sys.stdin).get('snapshots', [])
if snaps: print(snaps[-1]['snapshot'])
" 2>/dev/null)

    log "Restaurando snapshot: ${LATEST_SNAPSHOT}"

    curl -s -X POST "${ES_URL}/_snapshot/aurix-backups/${LATEST_SNAPSHOT}/_restore" \
        -H "Content-Type: application/json" \
        -d '{"ignore_unavailable": true, "include_global_state": false}'

    log "Restore Elasticsearch concluido"
else
    log "WARN: Nenhum snapshot Elasticsearch disponivel"
    ERRORS+=("elasticsearch_no_snapshots")
fi

# ===========================================================================
# 3. RESTORE CLICKHOUSE
# ===========================================================================
log ""
log "=== Restaurando ClickHouse ==="

CH_BACKUP_DIR=$(find "${RESTORE_DIR}/../" -path "*/clickhouse/*" -type d 2>/dev/null | head -1)

if [[ -n "${CH_BACKUP_DIR}" && -d "${CH_BACKUP_DIR}" ]]; then
    if command -v clickhouse-backup &>/dev/null; then
        log "Restaurando via clickhouse-backup..."
        clickhouse-backup restore "$(basename "${CH_BACKUP_DIR}")" || {
            log "WARN: Restore clickhouse-backup falhou"
            ERRORS+=("clickhouse_backup_restore_failed")
        }
    else
        log "Restaurando via TSV files..."
        for TSV_FILE in "${CH_BACKUP_DIR}"/*.tsv; do
            [[ -f "${TSV_FILE}" ]] || continue
            TABLE_NAME=$(basename "${TSV_FILE}" .tsv)
            log "  Importando: ${TABLE_NAME}"

            clickhouse-client \
                --host "${CH_HOST}" \
                --port "${CH_PORT}" \
                --user "${CH_USER}" \
                --password "${CH_PASSWORD}" \
                --database "${CH_DATABASE}" \
                --query "INSERT INTO ${TABLE_NAME} FORMAT TabSeparatedWithNamesAndTypes" \
                < "${TSV_FILE}" 2>/dev/null || {
                    log "    WARN: Falha ao importar ${TABLE_NAME}"
                    ERRORS+=("clickhouse_import_${TABLE_NAME}")
                }
        done
    fi
    log "ClickHouse restaurado"
else
    log "WARN: Nenhum backup ClickHouse encontrado para ${TIMESTAMP}"
    ERRORS+=("clickhouse_no_backup_found")
fi

# ===========================================================================
# 4. HEALTH CHECKS POS-RESTORE
# ===========================================================================
log ""
log "=== Health Checks Pos-Restore ==="

ALL_HEALTHY=true

# ClickHouse
if health_check "ClickHouse" "${CH_HOST}" "${CH_PORT}"; then
    TABLE_COUNT=$(clickhouse-client \
        --host "${CH_HOST}" --port "${CH_PORT}" \
        --user "${CH_USER}" --password "${CH_PASSWORD}" \
        --database "${CH_DATABASE}" \
        --query "SELECT count() FROM system.tables WHERE database = '${CH_DATABASE}'" 2>/dev/null || echo "0")
    log "  ClickHouse: ${TABLE_COUNT} tabelas"
else
    ALL_HEALTHY=false
fi

# TimescaleDB
if health_check "TimescaleDB" "${TS_HOST}" "${TS_PORT}"; then
    export PGPASSWORD="${TS_PASSWORD}"
    TS_TABLES=$(psql -h "${TS_HOST}" -p "${TS_PORT}" -U "${TS_USER}" -d "${TS_DATABASE}" \
        -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null || echo "0")
    unset PGPASSWORD
    log "  TimescaleDB: ${TS_TABLES} tabelas"
else
    ALL_HEALTHY=false
fi

# Elasticsearch
if health_check "Elasticsearch" "${ES_HOST}" "${ES_PORT}"; then
    ES_INDICES=$(curl -s "${ES_URL}/_cat/indices?format=json" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    log "  Elasticsearch: ${ES_INDICES} indices"
else
    ALL_HEALTHY=false
fi

# ===========================================================================
# 5. RELATORIO FINAL
# ===========================================================================
log ""
log "============================================="
if [[ ${#ERRORS[@]} -eq 0 && "${ALL_HEALTHY}" == "true" ]]; then
    log "  RESULTADO: SUCESSO"
else
    log "  RESULTADO: CONCLUIDO COM ERROS"
    for ERR in "${ERRORS[@]}"; do
        log "  - ${ERR}"
    done
fi
log "============================================="

exit ${#ERRORS[@]}
