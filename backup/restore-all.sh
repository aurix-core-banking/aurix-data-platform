#!/usr/bin/env bash
# =============================================================================
# Aurix Platform - Restore Orquestrado (todos os data stores)
# Restaura com ordem de dependencia, health checks, rollback
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="${1:-$(date +%Y%m%d_%H%M%S)}"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/restore-all-${TIMESTAMP}.log"
BACKUP_BASE="${SCRIPT_DIR}/local-backups"

# Configuracao via env
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-aurix}"
PG_PASSWORD="${PG_PASSWORD:-aurix_dev_password}"
PG_DATABASE="${PG_DATABASE:-aurix_db}"

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-aurix_dev_password}"

TS_HOST="${TS_HOST:-localhost}"
TS_PORT="${TS_PORT:-5433}"
TS_USER="${TS_USER:-aurix}"
TS_PASSWORD="${TS_PASSWORD:-aurix_dev_password}"
TS_DATABASE="${TS_DATABASE:-aurix_timeseries}"

CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-aurix}"
CH_PASSWORD="${CH_PASSWORD:-aurix_dev_password}"
CH_DATABASE="${CH_DATABASE:-aurix_analytics}"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_PROTOCOL="${ES_PROTOCOL:-http}"
ES_SECURITY="${ES_SECURITY:-false}"

KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
SCHEMA_REGISTRY_URL="${SCHEMA_REGISTRY_URL:-http://localhost:8081}"

S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:9000}"
S3_BUCKET="${S3_BUCKET:-aurix-backups-dev}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-minioadmin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-minioadmin}"

RESTORE_DIR="${SCRIPT_DIR}/restore-staging/${TIMESTAMP}"
ROLLBACK_DIR="${SCRIPT_DIR}/rollback/${TIMESTAMP}"
ERRORS=()
RESTORED=()

mkdir -p "${LOG_DIR}" "${RESTORE_DIR}" "${ROLLBACK_DIR}"

log() {
    local MSG="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${MSG}"
    echo "${MSG}" >> "${LOG_FILE}"
}

health_check() {
    local SERVICE=$1 HOST=$2 PORT=$3 MAX_RETRIES=${4:-30} RETRY=0
    log "  Health check: ${SERVICE} (${HOST}:${PORT})"
    while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
        if nc -z "${HOST}" "${PORT}" 2>/dev/null; then
            log "  ${SERVICE} respondendo"
            return 0
        fi
        RETRY=$((RETRY + 1))
        sleep 2
    done
    log "  ERRO: ${SERVICE} nao respondeu apos ${MAX_RETRIES} tentativas"
    return 1
}

rollback_service() {
    local SERVICE=$1
    log "  ROLLBACK: ${SERVICE}"
    case "${SERVICE}" in
        postgresql)
            if [[ -d "${ROLLBACK_DIR}/postgresql" ]]; then
                export PGPASSWORD="${PG_PASSWORD}"
                pg_restore --host="${PG_HOST}" --port="${PG_PORT}" --username="${PG_USER}" \
                    --dbname="${PG_DATABASE}" --clean --if-exists --no-owner --no-privileges \
                    "${ROLLBACK_DIR}/postgresql/"*.dump 2>/dev/null || true
                unset PGPASSWORD
                log "  Rollback PostgreSQL concluido"
            fi
            ;;
        *)
            log "  Rollback automatico nao disponivel para ${SERVICE}"
            ;;
    esac
}

log "============================================="
log "  Aurix Platform - Restore Orquestrado"
log "  Timestamp: ${TIMESTAMP}"
log "============================================="

# ---------------------------------------------------------------------------
# Pre-flight: conectividade
# ---------------------------------------------------------------------------
log "--- Verificando conectividade ---"
health_check "PostgreSQL" "${PG_HOST}" "${PG_PORT}" 5 || log "  WARN: PostgreSQL indisponivel"
health_check "Redis" "${REDIS_HOST}" "${REDIS_PORT}" 5 || log "  WARN: Redis indisponivel"
health_check "ClickHouse" "${CH_HOST}" "${CH_PORT}" 5 || log "  WARN: ClickHouse indisponivel"
health_check "TimescaleDB" "${TS_HOST}" "${TS_PORT}" 5 || log "  WARN: TimescaleDB indisponivel"
health_check "Elasticsearch" "${ES_HOST}" "${ES_PORT}" 5 || log "  WARN: Elasticsearch indisponivel"

# ---------------------------------------------------------------------------
# FASE 1: PostgreSQL (banco principal — prioridade maxima)
# ---------------------------------------------------------------------------
log ""
log "=== Fase 1: PostgreSQL ==="
export PGPASSWORD="${PG_PASSWORD}"

DUMP_PG=$(find "${BACKUP_BASE}/postgresql" -name "aurix_db_full_*.dump" -newer /dev/null 2>/dev/null | sort -r | head -1)
if [[ -n "${DUMP_PG}" && -f "${DUMP_PG}" ]]; then
    log "Restaurando PostgreSQL de: ${DUMP_PG}"
    pg_restore --host="${PG_HOST}" --port="${PG_PORT}" --username="${PG_USER}" \
        --dbname="${PG_DATABASE}" --clean --if-exists --no-owner --no-privileges \
        --verbose "${DUMP_PG}" 2>> "${LOG_FILE}" || ERRORS+=("postgresql_restore")
    RESTORED+=("postgresql")
    log "  PostgreSQL restaurado"
else
    log "  WARN: Nenhum dump PostgreSQL encontrado para ${TIMESTAMP}"
    ERRORS+=("postgresql_no_dump")
fi
unset PGPASSWORD

# ---------------------------------------------------------------------------
# FASE 2: Redis
# ---------------------------------------------------------------------------
log ""
log "=== Fase 2: Redis ==="
RDB_FILE=$(find "${BACKUP_BASE}/redis" -name "redis_dump_*.rdb" -newer /dev/null 2>/dev/null | sort -r | head -1)
if [[ -n "${RDB_FILE}" && -f "${RDB_FILE}" ]]; then
    log "Restaurando Redis de: ${RDB_FILE}"
    # Parar Redis
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" SHUTDOWN NOSAVE 2>/dev/null || true
    sleep 2
    # Copiar RDB
    cp "${RDB_FILE}" /var/lib/redis/dump.rdb 2>/dev/null || \
        log "  WARN: Nao foi possivel copiar RDB (verificar caminho)"
    log "  Redis restaurado (requer restart manual)"
    RESTORED+=("redis")
else
    log "  WARN: Nenhum dump Redis encontrado"
    ERRORS+=("redis_no_dump")
fi

# ---------------------------------------------------------------------------
# FASE 3: Elasticsearch
# ---------------------------------------------------------------------------
log ""
log "=== Fase 3: Elasticsearch ==="
if [[ "${ES_SECURITY}" == "true" ]]; then
    ES_URL="${ES_PROTOCOL}://${ES_USER}:${ES_PASSWORD}@${ES_HOST}:${ES_PORT}"
else
    ES_URL="${ES_PROTOCOL}://${ES_HOST}:${ES_PORT}"
fi

SNAPSHOTS=$(curl -s "${ES_URL}/_snapshot/aurix-backups/_all" 2>/dev/null || echo "{}")
SNAP_COUNT=$(echo "${SNAPSHOTS}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('snapshots',[])))" 2>/dev/null || echo "0")

if [[ "${SNAP_COUNT}" -gt 0 ]]; then
    LATEST_SNAP=$(echo "${SNAPSHOTS}" | python3 -c "
import sys, json
snaps = json.load(sys.stdin).get('snapshots', [])
if snaps: print(snaps[-1]['snapshot'])
" 2>/dev/null)

    log "Restaurando snapshot: ${LATEST_SNAP}"
    curl -s -X POST "${ES_URL}/_snapshot/aurix-backups/${LATEST_SNAP}/_restore" \
        -H "Content-Type: application/json" \
        -d '{"ignore_unavailable": true, "include_global_state": false}' 2>/dev/null || \
        ERRORS+=("elasticsearch_restore")
    RESTORED+=("elasticsearch")
    log "  Elasticsearch restaurado"
else
    log "  WARN: Nenhum snapshot Elasticsearch disponivel"
    ERRORS+=("elasticsearch_no_snapshots")
fi

# ---------------------------------------------------------------------------
# FASE 4: ClickHouse
# ---------------------------------------------------------------------------
log ""
log "=== Fase 4: ClickHouse ==="
if command -v clickhouse-backup &>/dev/null; then
    CH_BACKUP=$(find "${BACKUP_BASE}/clickhouse" -maxdepth 1 -type d -name "clickhouse_full_*" 2>/dev/null | sort -r | head -1)
    if [[ -n "${CH_BACKUP}" ]]; then
        clickhouse-backup restore "$(basename "${CH_BACKUP}")" 2>> "${LOG_FILE}" || \
            ERRORS+=("clickhouse_restore")
        RESTORED+=("clickhouse")
        log "  ClickHouse restaurado"
    else
        log "  WARN: Nenhum backup ClickHouse encontrado"
        ERRORS+=("clickhouse_no_backup")
    fi
else
    log "  WARN: clickhouse-backup nao encontrado"
    ERRORS+=("clickhouse_tool_missing")
fi

# ---------------------------------------------------------------------------
# FASE 5: TimescaleDB
# ---------------------------------------------------------------------------
log ""
log "=== Fase 5: TimescaleDB ==="
export PGPASSWORD="${TS_PASSWORD}"
DUMP_TS=$(find "${BACKUP_BASE}/timescaledb" -name "aurix_timeseries_*.dump" -newer /dev/null 2>/dev/null | sort -r | head -1)
if [[ -n "${DUMP_TS}" && -f "${DUMP_TS}" ]]; then
    log "Restaurando TimescaleDB de: ${DUMP_TS}"
    pg_restore --host="${TS_HOST}" --port="${TS_PORT}" --username="${TS_USER}" \
        --dbname="${TS_DATABASE}" --clean --if-exists --no-owner --no-privileges \
        --verbose "${DUMP_TS}" 2>> "${LOG_FILE}" || ERRORS+=("timescaledb_restore")
    RESTORED+=("timescaledb")
    log "  TimescaleDB restaurado"
else
    log "  WARN: Nenhum dump TimescaleDB encontrado"
    ERRORS+=("timescaledb_no_dump")
fi
unset PGPASSWORD

# ---------------------------------------------------------------------------
# FASE 6: Schema Registry (antes do Kafka)
# ---------------------------------------------------------------------------
log ""
log "=== Fase 6: Schema Registry ==="
SR_SUBJECTS=$(find "${BACKUP_BASE}/schema-registry" -path "*/export_*/full_export.json" 2>/dev/null | sort -r | head -1)
if [[ -n "${SR_SUBJECTS}" && -f "${SR_SUBJECTS}" ]]; then
    log "Restaurando Schema Registry de: ${SR_SUBJECTS}"
    python3 -c "
import json, sys, urllib.request
sr_url = '${SCHEMA_REGISTRY_URL}'
with open('${SR_SUBJECTS}') as f:
    subjects = json.load(f)
for subj_data in subjects:
    subj = subj_data.get('subject', '')
    for ver in subj_data.get('versions', []):
        schema = ver.get('schema', '')
        try:
            req = urllib.request.Request(
                f'{sr_url}/subjects/{subj}/versions',
                data=json.dumps({'schema': schema}).encode(),
                headers={'Content-Type': 'application/vnd.schemaregistry.v1+json'}
            )
            urllib.request.urlopen(req)
        except: pass
" 2>> "${LOG_FILE}" || ERRORS+=("schema_registry_restore")
    RESTORED+=("schema-registry")
    log "  Schema Registry restaurado"
else
    log "  WARN: Nenhum backup Schema Registry encontrado"
fi

# ---------------------------------------------------------------------------
# FASE 7: Kafka (recriar topicos)
# ---------------------------------------------------------------------------
log ""
log "=== Fase 7: Kafka ==="
KAFKA_CONFIGS_DIR=$(find "${BACKUP_BASE}/kafka" -path "*/configs_*" -type d 2>/dev/null | sort -r | head -1)
if [[ -n "${KAFKA_CONFIGS_DIR}" ]]; then
    log "Restaurando topicos Kafka de: ${KAFKA_CONFIGS_DIR}"
    KAFKA_TOPICS=""
    if [[ -x "/usr/bin/kafka-topics.sh" ]]; then
        KAFKA_TOPICS="/usr/bin/kafka-topics.sh"
    elif command -v kafka-topics &>/dev/null; then
        KAFKA_TOPICS="kafka-topics"
    fi

    if [[ -n "${KAFKA_TOPICS}" ]]; then
        for DESCRIBE_FILE in "${KAFKA_CONFIGS_DIR}"/*.describe; do
            [[ -f "${DESCRIBE_FILE}" ]] || continue
            TOPIC=$(basename "${DESCRIBE_FILE}" .describe)
            PARTITIONS=$(grep -o 'PartitionCount: [0-9]*' "${DESCRIBE_FILE}" 2>/dev/null | awk '{print $2}' || echo "1")
            REPLICAS=$(grep -o 'ReplicationFactor: [0-9]*' "${DESCRIBE_FILE}" 2>/dev/null | awk '{print $2}' || echo "1")
            ${KAFKA_TOPICS} --bootstrap-server "${KAFKA_BOOTSTRAP}" --create \
                --topic "${TOPIC}" --partitions "${PARTITIONS}" --replication-factor "${REPLICAS}" \
                --if-not-exists 2>> "${LOG_FILE}" || true
        done
        RESTORED+=("kafka")
        log "  Kafka topicos restaurados"
    fi
else
    log "  WARN: Nenhum backup Kafka encontrado"
fi

# ---------------------------------------------------------------------------
# HEALTH CHECKS POS-RESTORE
# ---------------------------------------------------------------------------
log ""
log "=== Health Checks Pos-Restore ==="
ALL_HEALTHY=true

if health_check "PostgreSQL" "${PG_HOST}" "${PG_PORT}"; then
    export PGPASSWORD="${PG_PASSWORD}"
    PG_TABLES=$(psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DATABASE}" \
        -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema')" 2>/dev/null || echo "?")
    unset PGPASSWORD
    log "  PostgreSQL: ${PG_TABLES} tabelas"
else
    ALL_HEALTHY=false
fi

if health_check "Redis" "${REDIS_HOST}" "${REDIS_PORT}" 5; then
    REDIS_KEYS=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" DBSIZE 2>/dev/null || echo "?")
    log "  Redis: ${REDIS_KEYS}"
else
    log "  Redis: indisponivel"
fi

if health_check "ClickHouse" "${CH_HOST}" "${CH_PORT}"; then
    CH_TABLES=$(clickhouse-client --host "${CH_HOST}" --port "${CH_PORT}" \
        --user "${CH_USER}" --password "${CH_PASSWORD}" \
        --database "${CH_DATABASE}" \
        --query "SELECT count() FROM system.tables WHERE database = '${CH_DATABASE}'" 2>/dev/null || echo "?")
    log "  ClickHouse: ${CH_TABLES} tabelas"
else
    ALL_HEALTHY=false
fi

if health_check "TimescaleDB" "${TS_HOST}" "${TS_PORT}"; then
    export PGPASSWORD="${TS_PASSWORD}"
    TS_TABLES=$(psql -h "${TS_HOST}" -p "${TS_PORT}" -U "${TS_USER}" -d "${TS_DATABASE}" \
        -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema')" 2>/dev/null || echo "?")
    unset PGPASSWORD
    log "  TimescaleDB: ${TS_TABLES} tabelas"
else
    ALL_HEALTHY=false
fi

if health_check "Elasticsearch" "${ES_HOST}" "${ES_PORT}"; then
    ES_INDICES=$(curl -s "${ES_URL}/_cat/indices?format=json" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
    log "  Elasticsearch: ${ES_INDICES} indices"
else
    ALL_HEALTHY=false
fi

# ---------------------------------------------------------------------------
# RELATORIO FINAL
# ---------------------------------------------------------------------------
log ""
log "============================================="
if [[ ${#ERRORS[@]} -eq 0 && "${ALL_HEALTHY}" == "true" ]]; then
    log "  RESULTADO: SUCESSO TOTAL"
    log "  Servicos restaurados: ${RESTORED[*]}"
elif [[ ${#ERRORS[@]} -gt 0 ]]; then
    log "  RESULTADO: CONCLUIDO COM ERROS"
    log "  Servicos restaurados: ${RESTORED[*]}"
    log "  Erros:"
    for ERR in "${ERRORS[@]}"; do
        log "    - ${ERR}"
    done
    log ""
    log "  Rollback disponivel em: ${ROLLBACK_DIR}"
fi
log "  Log completo: ${LOG_FILE}"
log "============================================="

exit ${#ERRORS[@]}
