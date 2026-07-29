-- AUREUS TimescaleDB - Time-series Database
-- Configuração para dados temporais e métricas

-- Habilitar extensão TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Tabela de métricas de transações em tempo real
CREATE TABLE IF NOT EXISTS metricas_transacoes (
    time TIMESTAMPTZ NOT NULL,
    conta_id BIGINT NOT NULL,
    tipo_transacao VARCHAR(50) NOT NULL,
    valor DECIMAL(19,4) NOT NULL,
    status VARCHAR(20) NOT NULL,
    canal VARCHAR(50),
    score_risco FLOAT,
    tempo_processamento_ms INTEGER,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    cidade VARCHAR(100),
    estado VARCHAR(2),
    tags JSONB
);

-- Converter para hypertable (TimescaleDB)
SELECT create_hypertable('metricas_transacoes', 'time', chunk_time_interval => INTERVAL '1 day');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_metricas_transacoes_conta_time ON metricas_transacoes (conta_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_metricas_transacoes_tipo_time ON metricas_transacoes (tipo_transacao, time DESC);
CREATE INDEX IF NOT EXISTS idx_metricas_transacoes_status_time ON metricas_transacoes (status, time DESC);

-- Tabela de métricas de performance do sistema
CREATE TABLE IF NOT EXISTS metricas_sistema (
    time TIMESTAMPTZ NOT NULL,
    servico VARCHAR(100) NOT NULL,
    endpoint VARCHAR(200),
    metodo_http VARCHAR(10),
    status_code INTEGER,
    tempo_resposta_ms INTEGER,
    memoria_uso_mb INTEGER,
    cpu_uso_percent FLOAT,
    conexoes_ativas INTEGER,
    requests_por_segundo FLOAT,
    error_rate FLOAT,
    tags JSONB
);

-- Converter para hypertable
SELECT create_hypertable('metricas_sistema', 'time', chunk_time_interval => INTERVAL '1 hour');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_metricas_sistema_servico_time ON metricas_sistema (servico, time DESC);
CREATE INDEX IF NOT EXISTS idx_metricas_sistema_status_time ON metricas_sistema (status_code, time DESC);

-- Tabela de métricas de negócio
CREATE TABLE IF NOT EXISTS metricas_negocio (
    time TIMESTAMPTZ NOT NULL,
    conta_id BIGINT,
    cliente_id BIGINT,
    segmento VARCHAR(50),
    tipo_operacao VARCHAR(50),
    valor_total DECIMAL(19,4),
    quantidade_operacoes INTEGER,
    receita DECIMAL(19,4),
    custo DECIMAL(19,4),
    margem DECIMAL(19,4),
    nps_score INTEGER,
    satisfacao FLOAT,
    tags JSONB
);

-- Converter para hypertable
SELECT create_hypertable('metricas_negocio', 'time', chunk_time_interval => INTERVAL '1 day');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_metricas_negocio_conta_time ON metricas_negocio (conta_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_metricas_negocio_segmento_time ON metricas_negocio (segmento, time DESC);

-- Tabela de eventos de risco em tempo real
CREATE TABLE IF NOT EXISTS eventos_risco_timeseries (
    time TIMESTAMPTZ NOT NULL,
    conta_id BIGINT NOT NULL,
    evento_id BIGINT NOT NULL,
    tipo_evento VARCHAR(50) NOT NULL,
    nivel_risco VARCHAR(20) NOT NULL,
    score_risco FLOAT NOT NULL,
    valor_envolvido DECIMAL(19,4),
    descricao TEXT,
    resolvido BOOLEAN DEFAULT FALSE,
    tempo_resolucao_minutos INTEGER,
    acao_tomada VARCHAR(100),
    usuario_responsavel VARCHAR(100),
    tags JSONB
);

-- Converter para hypertable
SELECT create_hypertable('eventos_risco_timeseries', 'time', chunk_time_interval => INTERVAL '1 day');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_eventos_risco_conta_time ON eventos_risco_timeseries (conta_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_eventos_risco_tipo_time ON eventos_risco_timeseries (tipo_evento, time DESC);
CREATE INDEX IF NOT EXISTS idx_eventos_risco_nivel_time ON eventos_risco_timeseries (nivel_risco, time DESC);

-- Tabela de dados de mercado
CREATE TABLE IF NOT EXISTS dados_mercado_timeseries (
    time TIMESTAMPTZ NOT NULL,
    indice VARCHAR(50) NOT NULL,
    valor FLOAT NOT NULL,
    variacao_percentual FLOAT,
    volume BIGINT,
    abertura FLOAT,
    fechamento FLOAT,
    maxima FLOAT,
    minima FLOAT,
    tags JSONB
);

-- Converter para hypertable
SELECT create_hypertable('dados_mercado_timeseries', 'time', chunk_time_interval => INTERVAL '1 day');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_dados_mercado_indice_time ON dados_mercado_timeseries (indice, time DESC);

-- Tabela de logs de auditoria em tempo real
CREATE TABLE IF NOT EXISTS logs_auditoria_timeseries (
    time TIMESTAMPTZ NOT NULL,
    usuario_id BIGINT,
    acao VARCHAR(100) NOT NULL,
    recurso VARCHAR(200),
    ip_address INET,
    user_agent TEXT,
    sucesso BOOLEAN,
    tempo_execucao_ms INTEGER,
    detalhes JSONB,
    tags JSONB
);

-- Converter para hypertable
SELECT create_hypertable('logs_auditoria_timeseries', 'time', chunk_time_interval => INTERVAL '1 day');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_logs_auditoria_usuario_time ON logs_auditoria_timeseries (usuario_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_logs_auditoria_acao_time ON logs_auditoria_timeseries (acao, time DESC);

-- Tabela de métricas de ML
CREATE TABLE IF NOT EXISTS metricas_ml_timeseries (
    time TIMESTAMPTZ NOT NULL,
    modelo VARCHAR(100) NOT NULL,
    versao VARCHAR(20) NOT NULL,
    conta_id BIGINT,
    tipo_previsao VARCHAR(50),
    valor_previsto FLOAT,
    valor_real FLOAT,
    confianca FLOAT,
    acuracia FLOAT,
    precisao FLOAT,
    recall FLOAT,
    f1_score FLOAT,
    tags JSONB
);

-- Converter para hypertable
SELECT create_hypertable('metricas_ml_timeseries', 'time', chunk_time_interval => INTERVAL '1 day');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_metricas_ml_modelo_time ON metricas_ml_timeseries (modelo, time DESC);
CREATE INDEX IF NOT EXISTS idx_metricas_ml_conta_time ON metricas_ml_timeseries (conta_id, time DESC);

-- Funções de agregação personalizadas
CREATE OR REPLACE FUNCTION calcular_media_movel(
    tabela_name TEXT,
    coluna_name TEXT,
    janela_horas INTEGER DEFAULT 24
) RETURNS TABLE (
    time TIMESTAMPTZ,
    media_movel FLOAT
) AS $$
BEGIN
    RETURN QUERY EXECUTE format('
        SELECT 
            time_bucket(INTERVAL ''1 hour'', time) as time,
            avg(%I) as media_movel
        FROM %I 
        WHERE time >= NOW() - INTERVAL ''%s hours''
        GROUP BY time_bucket(INTERVAL ''1 hour'', time)
        ORDER BY time
    ', coluna_name, tabela_name, janela_horas);
END;
$$ LANGUAGE plpgsql;

-- Função para detectar anomalias
CREATE OR REPLACE FUNCTION detectar_anomalias(
    tabela_name TEXT,
    coluna_name TEXT,
    threshold FLOAT DEFAULT 2.0
) RETURNS TABLE (
    time TIMESTAMPTZ,
    valor FLOAT,
    desvio_padrao FLOAT,
    eh_anomalia BOOLEAN
) AS $$
BEGIN
    RETURN QUERY EXECUTE format('
        WITH stats AS (
            SELECT 
                avg(%I) as media,
                stddev(%I) as desvio
            FROM %I 
            WHERE time >= NOW() - INTERVAL ''7 days''
        )
        SELECT 
            t.time,
            t.%I as valor,
            s.desvio as desvio_padrao,
            abs(t.%I - s.media) > (s.desvio * %s) as eh_anomalia
        FROM %I t
        CROSS JOIN stats s
        WHERE t.time >= NOW() - INTERVAL ''1 day''
        ORDER BY t.time DESC
    ', coluna_name, coluna_name, tabela_name, coluna_name, coluna_name, threshold, tabela_name);
END;
$$ LANGUAGE plpgsql;

-- Políticas de retenção de dados
-- Manter dados de métricas de transações por 1 ano
SELECT add_retention_policy('metricas_transacoes', INTERVAL '1 year');

-- Manter dados de métricas de sistema por 6 meses
SELECT add_retention_policy('metricas_sistema', INTERVAL '6 months');

-- Manter dados de métricas de negócio por 2 anos
SELECT add_retention_policy('metricas_negocio', INTERVAL '2 years');

-- Manter dados de eventos de risco por 3 anos
SELECT add_retention_policy('eventos_risco_timeseries', INTERVAL '3 years');

-- Manter dados de mercado por 5 anos
SELECT add_retention_policy('dados_mercado_timeseries', INTERVAL '5 years');

-- Manter logs de auditoria por 7 anos (compliance)
SELECT add_retention_policy('logs_auditoria_timeseries', INTERVAL '7 years');

-- Manter métricas de ML por 1 ano
SELECT add_retention_policy('metricas_ml_timeseries', INTERVAL '1 year');

-- Inserir dados de exemplo
INSERT INTO metricas_transacoes VALUES
(NOW() - INTERVAL '1 hour', 1, 'PIX', 500.00, 'APROVADA', 'MOBILE', 0.1, 150, -23.5505, -46.6333, 'São Paulo', 'SP', '{"canal": "mobile", "dispositivo": "iPhone"}'),
(NOW() - INTERVAL '30 minutes', 1, 'TED', 1000.00, 'APROVADA', 'WEB', 0.2, 200, -23.5505, -46.6333, 'São Paulo', 'SP', '{"canal": "web", "browser": "Chrome"}'),
(NOW() - INTERVAL '15 minutes', 2, 'PIX', 2500.00, 'APROVADA', 'MOBILE', 0.05, 120, -22.9068, -43.1729, 'Rio de Janeiro', 'RJ', '{"canal": "mobile", "dispositivo": "Samsung"}');

INSERT INTO metricas_sistema VALUES
(NOW() - INTERVAL '1 hour', 'aurix-core', '/api/transacoes', 'POST', 200, 150, 512, 25.5, 45, 10.5, 0.02, '{"ambiente": "producao"}'),
(NOW() - INTERVAL '30 minutes', 'aurix-pix', '/api/pix/transferencia', 'POST', 200, 120, 256, 15.2, 30, 15.8, 0.01, '{"ambiente": "producao"}'),
(NOW() - INTERVAL '15 minutes', 'aurix-credit', '/api/credito/analise', 'POST', 200, 300, 1024, 45.8, 20, 5.2, 0.05, '{"ambiente": "producao"}');

INSERT INTO dados_mercado_timeseries VALUES
(NOW() - INTERVAL '1 hour', 'CDI', 13.75, 0.1, 1000000, 13.70, 13.75, 13.80, 13.65, '{"fonte": "bacen"}'),
(NOW() - INTERVAL '30 minutes', 'SELIC', 10.50, 0.0, 2000000, 10.50, 10.50, 10.52, 10.48, '{"fonte": "bacen"}'),
(NOW() - INTERVAL '15 minutes', 'IPCA', 4.62, -0.1, 500000, 4.63, 4.62, 4.65, 4.60, '{"fonte": "ibge"}');

-- Criar views materializadas para relatórios
CREATE MATERIALIZED VIEW IF NOT EXISTS relatorio_transacoes_horario
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket(INTERVAL '1 hour', time) as hora,
    tipo_transacao,
    count(*) as total_transacoes,
    sum(valor) as valor_total,
    avg(valor) as valor_medio,
    avg(score_risco) as score_risco_medio,
    sum(CASE WHEN status = 'APROVADA' THEN 1 ELSE 0 END) as transacoes_aprovadas
FROM metricas_transacoes
WHERE time >= NOW() - INTERVAL '24 hours'
GROUP BY hora, tipo_transacao
ORDER BY hora DESC;

-- Adicionar política de refresh para a view materializada
SELECT add_continuous_aggregate_policy('relatorio_transacoes_horario',
    start_offset => INTERVAL '1 hour',
    end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 hour');

-- Configurar compressão para economizar espaço
ALTER TABLE metricas_transacoes SET (timescaledb.compress, timescaledb.compress_segmentby = 'conta_id');
ALTER TABLE metricas_sistema SET (timescaledb.compress, timescaledb.compress_segmentby = 'servico');
ALTER TABLE eventos_risco_timeseries SET (timescaledb.compress, timescaledb.compress_segmentby = 'conta_id');

-- Configurar compressão para dados mais antigos que 1 dia
SELECT add_compression_policy('metricas_transacoes', INTERVAL '1 day');
SELECT add_compression_policy('metricas_sistema', INTERVAL '1 day');
SELECT add_compression_policy('eventos_risco_timeseries', INTERVAL '1 day');

-- Mensagem de sucesso
DO $$
BEGIN
    RAISE NOTICE '=============================================';
    RAISE NOTICE 'AUREUS TimescaleDB - CONFIGURADO COM SUCESSO!';
    RAISE NOTICE '=============================================';
    RAISE NOTICE 'Tabelas criadas: 7';
    RAISE NOTICE 'Hypertables configuradas: 7';
    RAISE NOTICE 'Políticas de retenção: 7';
    RAISE NOTICE 'Políticas de compressão: 3';
    RAISE NOTICE 'Views materializadas: 1';
    RAISE NOTICE 'Funções personalizadas: 2';
    RAISE NOTICE 'Status: PRONTO PARA USO!';
    RAISE NOTICE '=============================================';
END $$;
