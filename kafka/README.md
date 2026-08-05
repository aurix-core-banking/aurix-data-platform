# AURIX Kafka — Docker Compose Profiles

Este diretório contém dois perfis de configuração Kafka:

| Perfil | Arquivo | Brokers | Fator de Replicação | Quando usar |
|--------|---------|---------|----------------------|-------------|
| **dev** | `docker-compose.yml` | 1 | 1 | Desenvolvimento local |
| **staging** | `docker-compose.staging.yml` | 3 | 3 | Homologação / pré-produção |

## Como usar

### Perfil Dev (padrão)
```bash
docker compose -f docker-compose.yml up -d
```

### Perfil Staging (3 brokers, replicação 3)
```bash
docker compose -f docker-compose.staging.yml up -d
```

### Parar os serviços
```bash
# Dev
docker compose -f docker-compose.yml down

# Staging
docker compose -f docker-compose.staging.yml down
```

## Variáveis de Ambiente

Copie `.env.example` para `.env` antes de iniciar:
```bash
cp .env.example .env
```

| Variável | Dev | Staging | Descrição |
|----------|-----|---------|-----------|
| `KAFKA_UI_PORT` | 8085 | 8085 | Porta host do Kafka UI |
| `KAFKA_REPLICATION_FACTOR` | 1 | 3 | Fator de replicação dos tópicos |

> **Nota:** A porta `8085` foi escolhida para o Kafka UI para evitar conflito com o Keycloak que usa a porta `8080` no `infra/docker-compose.yml`.

## Change Data Capture (CDC) com Debezium

O Kafka Connect captura mudanças do PostgreSQL (`aurix_db`, schema `aurix`) em tempo real e publica em tópicos `cdc.<schema>.<tabela>`.

### Conector

`connect-debezium-postgres.json` — `PostgresConnector` com `pgoutput`, snapshot inicial e publicação filtrada para:

| Tabela | Tópico |
|--------|--------|
| `contas` | `cdc.aurix.contas` |
| `clientes` | `cdc.aurix.clientes` |
| `transacoes` | `cdc.aurix.transacoes` |
| `pix_pagamentos` | `cdc.aurix.pix_pagamentos` |

### Deploy

O serviço `debezium-connect` já sobe junto com o stack (porta `8083`). Para registrar o conector:

```bash
# a partir de aurix-infrastructure/data-stack/
./scripts/deploy-debezium-connector.sh

# ou manualmente
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connect-debezium-postgres.json
```

### Verificar

```bash
# Status do conector
curl http://localhost:8083/connectors/aurix-postgres-cdc/status

# Tópicos criados
docker exec aurix-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep cdc
```

### Observações

- Requer `wal_level=logical`, `max_replication_slots` e `max_wal_senders` no PostgreSQL (já configurado no `data-stack/docker-compose.yml`).
- `snapshot.mode=initial`: as tabelas são copiadas uma vez na ativação e depois seguem o fluxo do WAL.
- `tombstones.on.delete=false`: DELETE publica evento com payload `null` e chave da linha removida.
- `decimal.handling.mode=double`: colunas `NUMERIC` viram `double` no JSON.
- `publication.autocreate.mode=filtered`: cria a publicação apenas com as tabelas da `table.include.list`.
- O backup por Kafka Connect S3 (Sink) permanece independente dos tópicos `cdc.*`.
