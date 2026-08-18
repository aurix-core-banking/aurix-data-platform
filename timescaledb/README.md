# Backup e Restore — TimescaleDB

## Estratégia

- **Snapshot lógico** via `pg_dump -Fc` (dump compactado) executado por
  `docker exec` no container `aurix-timescaledb`.
- Os dumps ficam em `backup/timescaledb/` e são válidos para restore em outra
  instância TimescaleDB/PostgreSQL (a extensão TimescaleDB é recriada no restore
  se o banco de destino a possuir).
- **Rotação**: o script de backup mantém os 7 snapshots mais recentes.

## Backup

```bash
# Manual
./timescaledb/backup.sh

# Agendamento diário (cron) às 02:00
0 2 * * * /caminho/do/repo/aurix-data-platform/timescaledb/backup.sh >> /var/log/timescaledb-backup.log 2>&1
```

## Restore

```bash
# Usa o dump mais recente
./timescaledb/restore.sh

# Usa um dump específico
./timescaledb/restore.sh backup/timescaledb/timescaledb_20260203-020000.dump
```

## Notas

- Variáveis configuráveis: `TIMESCALEDB_CONTAINER`, `TIMESCALEDB_DB`,
  `TIMESCALEDB_USER`, `TIMESCALEDB_PASSWORD`.
- Para disaster recovery físico (PITR), considere `pg_basebackup` + WAL
  arquivamento; o dump lógico cobre o RPO/RTO de desenvolvimento e o restore
  entre ambientes.
