# Backup e Restore — ClickHouse

## Estratégia

- **Backup nativo** via `BACKUP DATABASE ... TO File(...)` do ClickHouse (23.8+).
  Preserva tabelas, metadados e dados em formato compactado.
- O diretório `backup/clickhouse/` é montado em `/var/lib/clickhouse/backups`
  dentro do container (bind mount no `docker-compose.yml`).
- **Retenção**: o comando `SYSTEM CLEANUP` ou a exclusão manual de backups
  antigos em `backup/clickhouse/` deve ser feita conforme a política (sugestão:
  manter 7 backups diários).

## Backup

```bash
# Manual
./clickhouse/backup.sh

# Com rótulo próprio
./clickhouse/backup.sh 20260203-100000

# Agendamento diário (cron) às 01:00
0 1 * * * /caminho/do/repo/aurix-data-platform/clickhouse/backup.sh >> /var/log/clickhouse-backup.log 2>&1
```

## Restore

```bash
# Listar backups disponíveis (o script imprime antes de restaurar)
./clickhouse/restore.sh

# Restaurar um backup específico
./clickhouse/restore.sh 20260203-100000
```

## Notas

- O backup é feito por `docker exec` no container `aurix-clickhouse`.
  Sobrescreva as variáveis `CLICKHOUSE_CONTAINER`, `CLICKHOUSE_DB`,
  `CLICKHOUSE_USER` e `CLICKHOUSE_PASSWORD` conforme o ambiente.
- Para backup em S3/MinIO, substitua `File(...)` por
  `S3('https://bucket/path', 'key', 'secret')`.
