#!/usr/bin/env bash
# Backup de tópicos Kafka via Kafka Connect S3 sink.
#
# 1. Cria o bucket de backup no MinIO (se não existir)
# 2. Lista os tópicos reais do cluster
# 3. Aplica (cria/atualiza) o conector S3 sink com a lista de tópicos
#
# Uso:
#   ./kafka/backup-topics.sh
set -euo pipefail

KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
KAFKA_TOPICS_CMD="${KAFKA_TOPICS_CMD:-kafka-topics}"
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
MINIO_ALIAS="${MINIO_ALIAS:-aurix}"
MINIO_BUCKET="${MINIO_BUCKET:-aurix-kafka-backups}"
TOPICS_PATTERN="${TOPICS_PATTERN:-aurix.*}"

echo "==> Garantindo bucket ${MINIO_BUCKET} no MinIO"
docker exec aurix-minio mc mb --ignore-existing "minio/${MINIO_BUCKET}" 2>/dev/null || \
  mc alias set "${MINIO_ALIAS}" http://localhost:9000 "${MINIO_ACCESS_KEY:-aurix}" "${MINIO_SECRET_KEY:-aurix_dev_password}" \
  && mc mb --ignore-existing "${MINIO_ALIAS}/${MINIO_BUCKET}"

echo "==> Listando tópicos (padrão ${TOPICS_PATTERN})"
TOPICOS=$("${KAFKA_TOPICS_CMD}" --bootstrap-server "${KAFKA_BOOTSTRAP}" --list \
  | grep -E "${TOPICS_PATTERN}" || true)
if [[ -z "${TOPICOS}" ]]; then
  echo "Nenhum tópico encontrado com o padrão ${TOPICS_PATTERN}."
  exit 0
fi
echo "${TOPICOS}"

echo "==> Aplicando conector S3 sink com tópicos:"
PAYLOAD=$(python3 - <<EOF
import json
with open('kafka/connect-s3-sink.json') as f:
    cfg = json.load(f)
cfg['config']['topics'] = '${TOPICOS//$'\n'/,}'
print(json.dumps(cfg))
EOF
)
echo "${PAYLOAD}" | python3 -m json.tool

curl -sf -X PUT "${CONNECT_URL}/connectors/aurix-s3-sink-backup/config" \
  -H 'Content-Type: application/json' \
  -d "${PAYLOAD}" | python3 -m json.tool

echo "==> Status do conector:"
curl -sf "${CONNECT_URL}/connectors/aurix-s3-sink-backup/status" | python3 -m json.tool
