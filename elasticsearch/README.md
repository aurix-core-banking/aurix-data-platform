# Backup e Restore — Elasticsearch

## Estratégia

- **Snapshots** para repositório local filesystem (`/usr/share/elasticsearch/backups`,
  bind mount de `backup/elasticsearch/`), configurado via `-Epath.repo` no
  `docker-compose.yml`.
- **SLM (Snapshot Lifecycle Management)**: política `aurix-slm-policy`
  (definida em `snapshot-lifecycle.json`) cria snapshot diário às 03:00 UTC,
  com retenção de 30 dias (mín. 7, máx. 30).
- **ILM**: política `aurix-ilm-policy` gerencia o ciclo de vida dos índices
  (hot → warm → delete), reduzindo o volume de dados a indexar/snapshottar.

## Backup

```bash
# Registra repositório, aplica SLM/ILM e dispara snapshot imediato
./elasticsearch/backup.sh

# Aplicar política ILM manualmente
curl -X PUT http://localhost:9200/_ilm/policy/aurix-ilm-policy \
  -H 'Content-Type: application/json' \
  -d @<(python3 -c "import json;print(json.dumps(json.load(open('elasticsearch/snapshot-lifecycle.json'))['ilm_policy']['body']))")
```

## Restore

```bash
# Lista snapshots e restaura o informado
./elasticsearch/restore.sh
./elasticsearch/restore.sh aurix-snapshot-20260203
```

## Notas

- Variáveis configuráveis: `ES_URL`, `ELASTICSEARCH_USER`, `ELASTICSEARCH_PASSWORD`.
- Para ambientes com S3/MinIO, troque o repositório `fs` por `s3`
  (plugin `repository-s3`) e remova a restrição `path.repo`.
