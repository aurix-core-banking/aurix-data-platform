#!/usr/bin/env bash
# Backup do Elasticsearch: registra repositório de snapshots, aplica política
# SLM/ILM e dispara um snapshot imediato.
#
# Uso:
#   ./elasticsearch/backup.sh
set -euo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"
REPO="aurix-snapshots"
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backup/elasticsearch"
AUTH_ARGS=()
if [[ -n "${ELASTICSEARCH_USER:-}" && -n "${ELASTICSEARCH_PASSWORD:-}" ]]; then
  AUTH_ARGS=(-u "${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}")
fi

mkdir -p "${BACKUP_DIR}"

echo "==> Registrando repositório de snapshots '${REPO}'"
curl -sf -X PUT "${AUTH_ARGS[@]}" "${ES_URL}/_snapshot/${REPO}" \
  -H 'Content-Type: application/json' \
  -d "{\"type\": \"fs\", \"settings\": {\"location\": \"${BACKUP_DIR}\", \"compress\": true}}" \
  || echo "(repositório já existe ou não pôde ser recriado — continuando)"

echo "==> Aplicando política SLM aurix-slm-policy"
SLM=$(python3 -c "import json;print(json.dumps(json.load(open('elasticsearch/snapshot-lifecycle.json'))['slm_policy']['config']))" 2>/dev/null || true)
if [[ -n "${SLM}" ]]; then
  curl -sf -X PUT "${AUTH_ARGS[@]}" "${ES_URL}/_slm/policy/aurix-slm-policy" \
    -H 'Content-Type: application/json' \
    -d '{"name": "<aurix-snapshot-{now/d}>", "schedule": "0 0 3 * * ?", "repository": "'"${REPO}"'", "config": '"${SLM}"', "retention": {"expire_after": "30d", "min_count": 7, "max_count": 30}}' \
    || echo "AVISO: falha ao aplicar política SLM"
fi

echo "==> Disparando snapshot imediato aurix-snapshot-$(date +%Y%m%d-%H%M%S)"
curl -sf -X PUT "${AUTH_ARGS[@]}" "${ES_URL}/_snapshot/${REPO}/aurix-snapshot-$(date +%Y%m%d-%H%M%S)" \
  -H 'Content-Type: application/json' \
  -d '{"indices": "*,-.kibana*,-.security*,-.monitoring*", "ignore_unavailable": true, "include_global_state": false}'

echo "==> Backup disparado. Acompanhe com: curl ${ES_URL}/_snapshot/${REPO}/_status"
