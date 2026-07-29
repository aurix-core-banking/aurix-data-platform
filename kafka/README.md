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
