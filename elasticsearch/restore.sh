#!/usr/bin/env bash
# Restore do Elasticsearch a partir de um snapshot do repositório local.
#
# Uso:
#   ./elasticsearch/restore.sh [nome_do_snapshot]
set -euo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"
REPO="aurix-snapshots"
AUTH_ARGS=()
if [[ -n "${ELASTICSEARCH_USER:-}" && -n "${ELASTICSEARCH_PASSWORD:-}" ]]; then
  AUTH_ARGS=(-u "${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}")
fi

echo "==> Snapshots disponíveis no repositório '${REPO}':"
curl -sf "${AUTH_ARGS[@]}" "${ES_URL}/_snapshot/${REPO}/_all" \
  | python3 -m json.tool

SNAPSHOT="${1:-}"
if [[ -z "${SNAPSHOT}" ]]; then
  echo
  echo "Informe o nome do snapshot, ex.: ./elasticsearch/restore.sh aurix-snapshot-20260203"
  exit 1
fi

echo "==> Restaurando snapshot ${SNAPSHOT}"
curl -sf -X POST "${AUTH_ARGS[@]}" "${ES_URL}/_snapshot/${REPO}/${SNAPSHOT}/_restore" \
  -H 'Content-Type: application/json' \
  -d '{"indices": "*,-.kibana*,-.security*,-.monitoring*", "ignore_unavailable": true, "include_global_state": false}'

echo "==> Restore iniciado. Acompanhe com: curl ${ES_URL}/_snapshot/${REPO}/${SNAPSHOT}/_status"
