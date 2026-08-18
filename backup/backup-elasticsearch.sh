#!/usr/bin/env bash
# =============================================================================
# Aurix Platform - Backup Elasticsearch
# Snapshot API + procedimento de restore
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Configuracao via env
ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_PROTOCOL="${ES_PROTOCOL:-http}"
ES_USER="${ES_USER:-elastic}"
ES_PASSWORD="${ES_PASSWORD:-aurix_dev_password}"
ES_SECURITY="${ES_SECURITY:-false}"

SNAPSHOT_REPO="${SNAPSHOT_REPO:-aurix-backups}"
SNAPSHOT_NAME="snapshot_${TIMESTAMP}"
SNAPSHOT_LOCATION="${SNAPSHOT_LOCATION:-/usr/share/elasticsearch/data/backup}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Construir URL base do Elasticsearch
if [[ "${ES_SECURITY}" == "true" ]]; then
    ES_URL="${ES_PROTOCOL}://${ES_USER}:${ES_PASSWORD}@${ES_HOST}:${ES_PORT}"
else
    ES_URL="${ES_PROTOCOL}://${ES_HOST}:${ES_PORT}"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Inicio do backup Elasticsearch ==="

# 1. Verificar status do cluster
log "Verificando status do cluster..."
CLUSTER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${ES_URL}/_cluster/health")
if [[ "${CLUSTER_STATUS}" != "200" ]]; then
    log "ERRO: Cluster nao esta saudavel (HTTP ${CLUSTER_STATUS})"
    exit 1
fi
log "Cluster saudavel"

# 2. Criar/configurar repositorio de snapshot
log "Configurando repositorio de snapshots: ${SNAPSHOT_REPO}"
curl -s -X PUT "${ES_URL}/_snapshot/${SNAPSHOT_REPO}" \
    -H "Content-Type: application/json" \
    -d "{
        \"type\": \"fs\",
        \"settings\": {
            \"location\": \"${SNAPSHOT_LOCATION}\",
            \"compress\": true,
            \"max_snapshot_bytes_per_sec\": \"50mb\",
            \"max_restore_bytes_per_sec\": \"50mb\"
        }
    }"

# 3. Fechar indices para snapshot consistente (somente indices nao-criticos)
log "Obtendo lista de indices..."
INDICES=$(curl -s "${ES_URL}/_cat/indices?h=index&format=json" | \
    python3 -c "import sys,json; print(','.join([i['index'] for i in json.load(sys.stdin) if not i['index'].startswith('.')]))" 2>/dev/null || \
    curl -s "${ES_URL}/_cat/indices?h=index" | tr '\n' ',' | sed 's/,$//')

if [[ -z "${INDICES}" ]]; then
    log "Nenhum indice encontrado para backup"
    log "=== Backup Elasticsearch concluido (vazio) ==="
    exit 0
fi

# 4. Criar snapshot completo
log "Criando snapshot: ${SNAPSHOT_NAME}"
log "Indices: ${INDICES}"

HTTP_CODE=$(curl -s -o /tmp/es_snapshot_response.json -w "%{http_code}" \
    -X PUT "${ES_URL}/_snapshot/${SNAPSHOT_NAME}/_wait_for_completion" \
    -H "Content-Type: application/json" \
    -d "{
        \"indices\": \"${INDICES}\",
        \"ignore_unavailable\": true,
        \"include_global_state\": false
    }")

if [[ "${HTTP_CODE}" == "200" ]]; then
    SNAPSHOTS=$(cat /tmp/es_snapshot_response.json)
    log "Snapshot criado com sucesso"
    log "  Inicio: $(echo "${SNAPSHOTS}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('snapshot',{}).get('start_time','N/A'))" 2>/dev/null || echo 'N/A')"
else
    log "ERRO ao criar snapshot (HTTP ${HTTP_CODE})"
    cat /tmp/es_snapshot_response.json
    exit 1
fi

# 5. Listar snapshots para verificacao
log "Snapshots disponiveis:"
curl -s "${ES_URL}/_snapshot/${SNAPSHOT_NAME}/_all" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for snap in data.get('snapshots', []):
    print(f\"  {snap['snapshot']} - {snap['state']} - {snap.get('start_time','N/A')}\")
" 2>/dev/null || curl -s "${ES_URL}/_snapshot/_all" | python3 -m json.tool

# 6. Limpeza de snapshots antigos
log "Limpando snapshots com mais de ${RETENTION_DAYS} dias..."
SNAPSHOTS_TO_DELETE=$(curl -s "${ES_URL}/_snapshot/_all" | \
    python3 -c "
import sys, json
from datetime import datetime, timedelta
data = json.load(sys.stdin)
cutoff = datetime.utcnow() - timedelta(days=${RETENTION_DAYS})
for repo in data.get('repositories', []):
    for snap in data.get('repositories', [{}])[repo].get('snapshots', []):
        try:
            st = datetime.fromisoformat(snap['start_time'].replace('Z', '+00:00'))
            if st.replace(tzinfo=None) < cutoff:
                print(f\"{repo}/{snap['snapshot']}\")
        except: pass
" 2>/dev/null || true)

for SNAP_PATH in ${SNAPSHOTS_TO_DELETE}; do
    log "Removendo snapshot antigo: ${SNAP_PATH}"
    curl -s -X DELETE "${ES_URL}/_snapshot/${SNAP_PATH}"
done

# 7. Estatisticas do indice
log "Estatisticas de armazenamento:"
curl -s "${ES_URL}/_cat/allocation?v&h=shards,disk.indices,disk.used,disk.avail,disk.total" 2>/dev/null || true

log "=== Backup Elasticsearch concluido ==="

# =============================================================================
# PROCEDIMENTO DE RESTORE (executar manualmente)
# =============================================================================
cat << 'RESTORE_INFO'

--- PROCEDIMENTO DE RESTORE ELASTICSEARCH ---

Para restaurar um snapshot, execute:

  # 1. Listar snapshots disponiveis
  curl -X GET "http://ES_HOST:9200/_snapshot/aurix-backups/_all"

  # 2. Fechar indices que serao restaurados
  curl -X POST "http://ES_HOST:9200/INDEX_NAME/_close"

  # 3. Restaurar snapshot (substitui indices existentes)
  curl -X POST "http://ES_HOST:9200/_snapshot/aurix-backups/SNAPSHOT_NAME/_restore" \
    -H "Content-Type: application/json" \
    -d '{
      "indices": "INDEX1,INDEX2",
      "ignore_unavailable": true,
      "include_global_state": false
    }'

  # 4. Reabrir indices
  curl -X POST "http://ES_HOST:9200/INDEX_NAME/_open"

  # 5. Verificar contagem de documentos
  curl -X GET "http://ES_HOST:9200/_cat/indices?v&h=index,health,docs.count,store.size"

RESTORE_INFO
