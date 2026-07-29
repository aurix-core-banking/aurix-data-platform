-- AUREUS Analytics Database Schema
-- ClickHouse para análise de dados financeiros

-- Tabela de transações para analytics
CREATE TABLE IF NOT EXISTS transacoes_analytics (
    id UInt64,
    conta_id UInt64,
    tipo_transacao String,
    valor Decimal(19,4),
    data_transacao DateTime,
    status String,
    canal String,
    dispositivo String,
    ip_address String,
    user_agent String,
    latitude Float64,
    longitude Float64,
    cidade String,
    estado String,
    pais String,
    score_risco Float32,
    aprovada UInt8,
    tempo_processamento_ms UInt32,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(data_transacao)
ORDER BY (conta_id, data_transacao, id)
SETTINGS index_granularity = 8192;

-- Tabela de contas para analytics
CREATE TABLE IF NOT EXISTS contas_analytics (
    conta_id UInt64,
    cliente_id UInt64,
    tipo_conta String,
    saldo_atual Decimal(19,4),
    limite_credito Decimal(19,4),
    data_abertura Date,
    status String,
    segmento String,
    score_credito Float32,
    renda_mensal Decimal(19,4),
    idade UInt8,
    genero String,
    estado_civil String,
    escolaridade String,
    profissao String,
    cidade String,
    estado String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(toDate(created_at))
ORDER BY (conta_id, created_at)
SETTINGS index_granularity = 8192;

-- Tabela de eventos de risco
CREATE TABLE IF NOT EXISTS eventos_risco_analytics (
    evento_id UInt64,
    conta_id UInt64,
    tipo_evento String,
    nivel_risco String,
    score_risco Float32,
    descricao String,
    valor_envolvido Decimal(19,4),
    data_evento DateTime,
    resolvido UInt8,
    tempo_resolucao_minutos UInt32,
    acao_tomada String,
    usuario_responsavel String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(data_evento)
ORDER BY (conta_id, data_evento, evento_id)
SETTINGS index_granularity = 8192;

-- Tabela de métricas de performance
CREATE TABLE IF NOT EXISTS metricas_performance (
    metrica_id UInt64,
    servico String,
    endpoint String,
    metodo_http String,
    status_code UInt16,
    tempo_resposta_ms UInt32,
    memoria_uso_mb UInt32,
    cpu_uso_percent Float32,
    timestamp DateTime,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (servico, timestamp, metrica_id)
SETTINGS index_granularity = 8192;

-- Tabela de logs de auditoria
CREATE TABLE IF NOT EXISTS logs_auditoria_analytics (
    log_id UInt64,
    usuario_id UInt64,
    acao String,
    recurso String,
    ip_address String,
    user_agent String,
    sucesso UInt8,
    detalhes String,
    timestamp DateTime,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (usuario_id, timestamp, log_id)
SETTINGS index_granularity = 8192;

-- Tabela de dados de mercado
CREATE TABLE IF NOT EXISTS dados_mercado (
    data Date,
    indice String,
    valor Float64,
    variacao_percentual Float32,
    volume UInt64,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(data)
ORDER BY (indice, data)
SETTINGS index_granularity = 8192;

-- Tabela de previsões ML
CREATE TABLE IF NOT EXISTS previsoes_ml (
    previsao_id UInt64,
    modelo String,
    versao String,
    conta_id UInt64,
    tipo_previsao String,
    valor_previsto Float64,
    confianca Float32,
    data_previsao Date,
    data_criacao DateTime,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(data_previsao)
ORDER BY (conta_id, data_previsao, previsao_id)
SETTINGS index_granularity = 8192;

-- Inserir dados de exemplo
INSERT INTO contas_analytics VALUES
(1, 1001, 'CORRENTE', 5000.00, 10000.00, '2024-01-15', 'ATIVA', 'PREMIUM', 750.5, 15000.00, 35, 'M', 'CASADO', 'SUPERIOR', 'ENGENHEIRO', 'São Paulo', 'SP', now()),
(2, 1002, 'POUPANCA', 25000.00, 0.00, '2024-02-20', 'ATIVA', 'VIP', 850.0, 25000.00, 42, 'F', 'SOLTEIRA', 'POS_GRADUACAO', 'MEDICA', 'Rio de Janeiro', 'RJ', now()),
(3, 1003, 'CORRENTE', 1200.00, 5000.00, '2024-03-10', 'ATIVA', 'BASICO', 650.0, 8000.00, 28, 'M', 'SOLTEIRO', 'SUPERIOR', 'DESENVOLVEDOR', 'Belo Horizonte', 'MG', now());

INSERT INTO transacoes_analytics VALUES
(1, 1, 'PIX', 500.00, '2024-01-20 10:30:00', 'APROVADA', 'MOBILE', 'iPhone 14', '192.168.1.100', 'Mozilla/5.0', -23.5505, -46.6333, 'São Paulo', 'SP', 'Brasil', 0.1, 1, 150, now()),
(2, 1, 'TED', 1000.00, '2024-01-21 14:15:00', 'APROVADA', 'WEB', 'Chrome', '192.168.1.100', 'Mozilla/5.0', -23.5505, -46.6333, 'São Paulo', 'SP', 'Brasil', 0.2, 1, 200, now()),
(3, 2, 'PIX', 2500.00, '2024-01-22 09:45:00', 'APROVADA', 'MOBILE', 'Samsung Galaxy', '192.168.1.101', 'Mozilla/5.0', -22.9068, -43.1729, 'Rio de Janeiro', 'RJ', 'Brasil', 0.05, 1, 120, now());

INSERT INTO dados_mercado VALUES
('2024-01-20', 'CDI', 13.75, 0.1, 1000000, now()),
('2024-01-20', 'SELIC', 10.50, 0.0, 2000000, now()),
('2024-01-20', 'IPCA', 4.62, -0.1, 500000, now());
