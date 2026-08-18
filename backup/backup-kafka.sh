#!/usr/bin/env bash
# =============================================================================
# Aurix Platform - Backup Kafka
# Exportacao de topic configs, offsets de consumer groups, compactacao de logs
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${SCRIPT_DIR}/local-backups/kafka"

# Configuracao via env
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
KAFKA_HOME="${KAFKA_HOME:-/usr}"

S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:9000}"
S3_BUCKET="${S3_BUCKET:-aurix-backups-dev}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-minioadmin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-minioadmin}"

RETENTION_DAYS="${RETENTION_DAYS:-30}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Inicio do backup Kafka ==="

mkdir -p "${BACKUP_DIR}"

# 1. Listar todos os topicos
log "Listando topicos..."
TOPICS_FILE="${BACKUP_DIR}/topics_${TIMESTAMP}.txt"
${KAFKA_HOME}/bin/kafka-topics.sh \
    --bootstrap-server "${KAFKA_BOOTSTRAP}" \
    --list > "${TOPICS_FILE}" 2>/dev/null || \
    kafka-topics --bootstrap-server "${KAFKA_BOOTSTRAP}" --list > "${TOPICS_FILE}"

TOPIC_COUNT=$(wc -l < "${TOPICS_FILE}")
log "Total de topicos: ${TOPIC_COUNT}"

# 2. Exportar configuracao de cada topico
log "Exportando configuracoes dos topicos..."
TOPICS_CONFIG_DIR="${BACKUP_DIR}/configs_${TIMESTAMP}"
mkdir -p "${TOPICS_CONFIG_DIR}"

while IFS= read -r TOPIC; do
    [[ -z "${TOPIC}" ]] && continue
    log "  Topico: ${TOPIC}"

    ${KAFKA_HOME}/bin/kafka-topics.sh \
        --bootstrap-server "${KAFKA_BOOTSTRAP}" \
        --describe \
        --topic "${TOPIC}" \
        --with-overrides > "${TOPICS_CONFIG_DIR}/${TOPIC}.describe" 2>/dev/null || \
        kafka-topics --bootstrap-server "${KAFKA_BOOTSTRAP}" \
            --describe --topic "${TOPIC}" --with-overrides > "${TOPICS_CONFIG_DIR}/${TOPIC}.describe"

    ${KAFKA_HOME}/bin/kafka-configs.sh \
        --bootstrap-server "${KAFKA_BOOTSTRAP}" \
        --describe \
        --entity-type topics \
        --entity-name "${TOPIC}" > "${TOPICS_CONFIG_DIR}/${TOPIC}.configs" 2>/dev/null || \
        kafka-configs --bootstrap-server "${KAFKA_BOOTSTRAP}" \
            --describe --entity-type topics --entity-name "${TOPIC}" > "${TOPICS_CONFIG_DIR}/${TOPIC}.configs"

done < "${TOPICS_FILE}"

log "Configuracoes exportadas para ${TOPICS_CONFIG_DIR}"

# 3. Exportar offsets dos consumer groups
log "Exportando offsets dos consumer groups..."
OFFSETS_DIR="${BACKUP_DIR}/offsets_${TIMESTAMP}"
mkdir -p "${OFFSETS_DIR}"

CONSUMER_GROUPS=$(${KAFKA_HOME}/bin/kafka-consumer-groups.sh \
    --bootstrap-server "${KAFKA_BOOTSTRAP}" \
    --list 2>/dev/null || \
    kafka-consumer-groups --bootstrap-server "${KAFKA_BOOTSTRAP}" --list)

GROUP_COUNT=0
while IFS= read -r GROUP; do
    [[ -z "${GROUP}" ]] && continue
    log "  Consumer group: ${GROUP}"

    ${KAFKA_HOME}/bin/kafka-consumer-groups.sh \
        --bootstrap-server "${KAFKA_BOOTSTRAP}" \
        --describe \
        --group "${GROUP}" > "${OFFSETS_DIR}/${GROUP}.offsets" 2>/dev/null || \
        kafka-consumer-groups --bootstrap-server "${KAFKA_BOOTSTRAP}" \
            --describe --group "${GROUP}" > "${OFFSETS_DIR}/${GROUP}.offsets" 2>/dev/null || true

    GROUP_COUNT=$((GROUP_COUNT + 1))
done <<< "${CONSUMER_GROUPS}"

log "Offsets exportados para ${GROUP_COUNT} consumer groups"

# 4. Salvar metadados consolidados
log "Gerando metadados consolidados..."
cat > "${BACKUP_DIR}/metadata_${TIMESTAMP}.json" << EOF
{
    "timestamp": "${TIMESTAMP}",
    "kafka_bootstrap": "${KAFKA_BOOTSTRAP}",
    "topic_count": ${TOPIC_COUNT},
    "consumer_group_count": ${GROUP_COUNT},
    "backup_host": "$(hostname)"
}
EOF

# 5. Trigger de log compaction (forcar limpeza de logs antigos)
log "Verificando topicos com cleanup.policy=compact..."
while IFS= read -r TOPIC; do
    [[ -z "${TOPIC}" ]] && continue
    POLICY=$(grep -o 'cleanup.policy=[a-z,]*' "${TOPICS_CONFIG_DIR}/${TOPIC}.configs" 2>/dev/null || echo "")
    if [[ "${POLICY}" == *"compact"* ]]; then
        log "  Topico compactavel: ${TOPIC} (${POLICY})"
    fi
done < "${TOPICS_FILE}"

# 6. Upload para S3/MinIO
log "Upload para S3..."
export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
export AWS_DEFAULT_REGION="us-east-1"

if command -v aws &>/dev/null; then
    aws --endpoint-url "${S3_ENDPOINT}" s3 cp \
        "${BACKUP_DIR}/" \
        "s3://${S3_BUCKET}/kafka/${TIMESTAMP}/" \
        --recursive \
        --exclude "*.log"
    log "Upload S3 concluido"
else
    log "WARN: aws CLI nao encontrado, backup mantido localmente"
fi

# 7. Limpeza de backups antigos
log "Limpando backups com mais de ${RETENTION_DAYS} dias..."
find "${BACKUP_DIR}" -maxdepth 1 -type d -name "20*" -mtime "+${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true

log "=== Backup Kafka concluido ==="
