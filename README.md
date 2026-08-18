# Aurix Data Platform

ClickHouse (OLAP), TimescaleDB (time-series), Kafka (3-broker staging), Debezium CDC, Elasticsearch.

## Stack

- **ClickHouse 23.8** — analytics OLAP (7 tabelas MergeTree)
- **TimescaleDB 2.11** — time-series (11 hypertables + continuous aggregates)
- **Kafka 3-broker** — event streaming (replication factor 3)
- **Debezium 2.7** — CDC from PostgreSQL (4 tabelas)
- **Elasticsearch 8.11** — full-text search + logs

## ClickHouse

```bash
cd clickhouse && docker-compose up -d
```

| Tabela | Engine | Partição | Descrição |
|---|---|---|---|
| `transacoes_analytics` | MergeTree | `toYYYYMM(data_transacao)` | Analytics de transações |
| `contas_analytics` | MergeTree | `toYYYYMM(created_at)` | Analytics de contas |
| `eventos_risco_analytics` | MergeTree | `toYYYYMM(data_evento)` | Eventos de risco |
| `metricas_performance` | MergeTree | `toYYYYMM(timestamp)` | Métricas de performance |
| `logs_auditoria_analytics` | MergeTree | `toYYYYMM(timestamp)` | Logs de auditoria |
| `dados_mercado` | MergeTree | `toYYYYMM(data)` | Dados de mercado |
| `previsoes_ml` | MergeTree | `toYYYYMM(data_previsao)` | Previsões ML |

## TimescaleDB

```bash
cd timescaledb && docker-compose up -d
```

11 hypertables com continuous aggregates e retention policies:

| Hypertable | Chunk Interval | Retention | Descrição |
|---|---|---|---|
| `metricas_transacoes` | 1 day | 1 year | Métricas de transações |
| `metricas_sistema` | 1 hour | 6 months | Métricas de sistema |
| `metricas_negocio` | 1 day | 2 years | Métricas de negócio |
| `eventos_risco_timeseries` | 1 day | 3 years | Eventos de risco |
| `dados_mercado_timeseries` | 1 day | 5 years | Dados de mercado |
| `logs_auditoria_timeseries` | 1 day | 7 years | Logs de auditoria (LGPD) |
| `metricas_ml_timeseries` | 1 day | 1 year | Métricas de modelos ML |
| `ts_metricas_performance` | 1 day | 90 days | Performance (P95/P99) |
| `ts_saldos_diarios` | 7 days | — | Saldos diários |
| `ts_volume_transacoes` | 1 day | 2 years | Volume de transações |
| `ts_audit_log` | 1 day | 365 days | Audit logs |

## Kafka (staging — 3 brokers)

```bash
cd kafka && docker-compose -f docker-compose.staging.yml up -d
```

- **Replication factor**: 3
- **Min ISR**: 2
- **12 partições** por tópico

## Debezium CDC

```bash
cd kafka && bash ../aurix-infrastructure/data-stack/scripts/deploy-debezium-connector.sh
```

Captura: `aurix.contas`, `aurix.clientes`, `aurix.transacoes`, `aurix.pix_pagamentos`

## Relacionados

- [aurix-data-pipelines](https://github.com/aurix-core-banking/aurix-data-pipelines)
- [aurix-infrastructure](https://github.com/aurix-core-banking/aurix-infrastructure)
