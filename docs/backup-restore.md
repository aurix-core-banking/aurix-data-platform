# Backup e Restore — Aurix Data Platform

Estratégia de backup/restore dos data stores da plataforma de dados, com
procedimento documentado de restore e teste periódico de recuperação (DR drill).

## Visão geral

| Componente | Mecanismo | Frequência | Destino | Scripts |
|---|---|---|---|---|
| ClickHouse | Backup nativo (`BACKUP DATABASE`) | Diário 01:00 | `backup/clickhouse/` | `clickhouse/backup.sh`, `clickhouse/restore.sh` |
| TimescaleDB | `pg_dump -Fc` (dump lógico) | Diário 02:00 | `backup/timescaledb/` | `timescaledb/backup.sh`, `timescaledb/restore.sh` |
| Elasticsearch | Snapshot `fs` + SLM/ILM | Diário 03:00 UTC | `backup/elasticsearch/` | `elasticsearch/backup.sh`, `elasticsearch/restore.sh` |
| Kafka | Kafka Connect S3 sink | Contínuo (10 min) | S3/MinIO `aurix-kafka-backups` | `kafka/backup-topics.sh`, `kafka/connect-s3-sink.json` |

> PostgreSQL transacional (`aurix_db`) e Redis têm estratégia própria no
> `aurix-infrastructure` (scripts `backup-restore-postgres`).

## Procedimentos de restore

### ClickHouse

```bash
# Listar backups e restaurar um específico
./clickhouse/restore.sh
./clickhouse/restore.sh 20260203-100000
```

### TimescaleDB

```bash
# Restaurar o dump mais recente (ou um específico)
./timescaledb/restore.sh
./timescaledb/restore.sh backup/timescaledb/timescaledb_20260203-020000.dump
```

### Elasticsearch

```bash
# Listar snapshots e restaurar
./elasticsearch/restore.sh
./elasticsearch/restore.sh aurix-snapshot-20260203
```

### Kafka

```bash
# Replay dos tópicos a partir do bucket S3 (ver kafka/README.md)
# 1. Recriar tópicos com a mesma configuração
# 2. Aplicar S3 source connector para reprocessar os arquivos JSON
```

## DR Drill (teste periódico de restore)

Para garantir que os backups são restauráveis, execute trimestralmente:

1. **Preparação**: provisionar um ambiente de DR (ou containers descartáveis)
   com as mesmas versões das imagens (`clickhouse/clickhouse-server:23.8`,
   `timescale/timescaledb:pg15`, `elasticsearch:8.11`, `cp-kafka:7.4`).
2. **Execução** (RTO/RPO alvo entre parênteses):
   - Restaurar ClickHouse (< 60 min).
   - Restaurar TimescaleDB (< 60 min).
   - Restaurar Elasticsearch (< 30 min).
   - Replay de 1 tópico Kafka de produção (< 120 min).
3. **Validação**: comparar contagens de linhas/registros e checksum dos
   componentes restaurados contra o ambiente de origem.
4. **Registro**: documentar data, duração, desvios e ações corretivas no
   runbook de DR (`aurix-docs/05-infrastructure/infrastructure/dr-procedimento.md`).

Checklist do DR drill:

- [ ] Snapshots mais recentes de todas as tecnologias existem no destino
- [ ] Restore ClickHouse executado e validado
- [ ] Restore TimescaleDB executado e validado
- [ ] Restore Elasticsearch executado e validado
- [ ] Replay Kafka executado e validado
- [ ] Tempos dentro do RTO e perda de dados dentro do RPO
- [ ] Incidente/ações registradas e acompanhadas

## Cron (exemplo)

```cron
0 1 * * *  /caminho/aurix-data-platform/clickhouse/backup.sh   >> /var/log/backup-clickhouse.log 2>&1
0 2 * * *  /caminho/aurix-data-platform/timescaledb/backup.sh  >> /var/log/backup-timescaledb.log 2>&1
0 3 * * *  /caminho/aurix-data-platform/elasticsearch/backup.sh >> /var/log/backup-elasticsearch.log 2>&1
*/10 * * * * curl -s http://localhost:8083/connectors/aurix-s3-sink-backup/status | grep -q RUNNING || /caminho/aurix-data-platform/kafka/backup-topics.sh
```
