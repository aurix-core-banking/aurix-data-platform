-- ============================================================
-- TimescaleDB — Hypertables para séries temporais
-- Rodar: psql -h localhost -p 5433 -U aurix -d aurix_timeseries
-- ============================================================

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ──────────────────────────────────────────────────────────────
-- 1. Métricas de performance (latência, throughput, erros)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ts_metricas_performance (
    time            TIMESTAMPTZ NOT NULL,
    servico         TEXT NOT NULL,
    endpoint        TEXT NOT NULL,
    metodo_http     TEXT NOT NULL,
    status_code     INTEGER,
    latencia_ms     DOUBLE PRECISION,
    throughput_rps  DOUBLE PRECISION,
    taxa_erro       DOUBLE PRECISION,
    cpu_usage       DOUBLE PRECISION,
    memory_usage    DOUBLE PRECISION,
    tags            JSONB DEFAULT '{}'
);

SELECT create_hypertable('ts_metricas_performance', 'time',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

CREATE INDEX idx_ts_perf_servico ON ts_metricas_performance (servico, time DESC);
CREATE INDEX idx_ts_perf_endpoint ON ts_metricas_performance (endpoint, time DESC);

-- ──────────────────────────────────────────────────────────────
-- 2. Saldos diários de contas (snapshots)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ts_saldos_diarios (
    time            TIMESTAMPTZ NOT NULL,
    conta_id        BIGINT NOT NULL,
    saldo           NUMERIC(15,2),
    limite_credito  NUMERIC(15,2),
    Limite_disponivel NUMERIC(15,2),
    tipo_conta      TEXT
);

SELECT create_hypertable('ts_saldos_diarios', 'time',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE);

CREATE INDEX idx_ts_saldos_conta ON ts_saldos_diarios (conta_id, time DESC);

-- ──────────────────────────────────────────────────────────────
-- 3. Volume de transações por hora
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ts_volume_transacoes (
    time            TIMESTAMPTZ NOT NULL,
    tipo_transacao  TEXT NOT NULL,
    qtd_transacoes  INTEGER,
    valor_total     NUMERIC(18,2),
    ticket_medio    NUMERIC(15,2),
    contas_unicas   INTEGER
);

SELECT create_hypertable('ts_volume_transacoes', 'time',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

CREATE INDEX idx_ts_vol_tipo ON ts_volume_transacoes (tipo_transacao, time DESC);

-- ──────────────────────────────────────────────────────────────
-- 4. Logs de auditoria (temporal)
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ts_audit_log (
    time            TIMESTAMPTZ NOT NULL,
    servico         TEXT NOT NULL,
    acao            TEXT NOT NULL,
    entidade        TEXT NOT NULL,
    usuario_id      BIGINT,
    nivel           TEXT DEFAULT 'INFO',
    ip_origem       TEXT,
    duracao_ms      DOUBLE PRECISION
);

SELECT create_hypertable('ts_audit_log', 'time',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

CREATE INDEX idx_ts_audit_servico ON ts_audit_log (servico, time DESC);
CREATE INDEX idx_ts_audit_entidade ON ts_audit_log (entidade, time DESC);

-- ──────────────────────────────────────────────────────────────
-- 5. Continuous Aggregates (materialized views)
-- ──────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS ts_metricas_hora
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    servico,
    COUNT(*) AS total_requests,
    AVG(latencia_ms) AS latencia_media,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latencia_ms) AS latencia_p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latencia_ms) AS latencia_p99,
    SUM(CASE WHEN status_code >= 500 THEN 1 ELSE 0 END)::DOUBLE PRECISION / COUNT(*) * 100 AS taxa_erro
FROM ts_metricas_performance
GROUP BY bucket, servico
WITH NO DATA;

-- Refresh policy: atualiza a cada 5 minutos
SELECT add_continuous_aggregate_policy('ts_metricas_hora',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '5 minutes',
    schedule_interval => INTERVAL '5 minutes',
    if_not_exists => TRUE);

-- ──────────────────────────────────────────────────────────────
-- 6. Retention policies
-- ──────────────────────────────────────────────────────────────
SELECT add_retention_policy('ts_metricas_performance', INTERVAL '90 days', if_not_exists => TRUE);
SELECT add_retention_policy('ts_audit_log', INTERVAL '365 days', if_not_exists => TRUE);
SELECT add_retention_policy('ts_volume_transacoes', INTERVAL '2 years', if_not_exists => TRUE);

-- ──────────────────────────────────────────────────────────────
-- 7. Compression policies
-- ─────────────────────────────────────────_aggregate_policy
SELECT add_compression_policy('ts_metricas_performance', INTERVAL '7 days', if_not_exists => TRUE);
SELECT add_compression_policy('ts_audit_log', INTERVAL '30 days', if_not_exists => TRUE);
