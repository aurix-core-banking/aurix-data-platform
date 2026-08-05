# Backup e Restore — Kafka

## Estratégia

- **Backup contínuo de tópicos** via Kafka Connect **S3 sink** (conector
  `aurix-s3-sink-backup`, definido em `connect-s3-sink.json`), gravando JSON em
  bucket S3/MinIO (`aurix-kafka-backups`) com rotação a cada 10 minutos.
- O conector usa `StringConverter`/`JsonConverter` (sem Schema Registry),
  mantendo compatibilidade com o JsonConverter do JsonFormat para replay.
- Os tópicos protegidos incluem o tópico de **outbox** (`aurix.outbox`),
  essencial para recuperação de eventos não entregues.

## Backup

```bash
# Cria o bucket e aplica o conector com os tópicos reais do cluster
./kafka/backup-topics.sh

# Aplicar sem listar (usar a lista fixa do connect-s3-sink.json)
curl -X PUT http://localhost:8083/connectors/aurix-s3-sink-backup/config \
  -H 'Content-Type: application/json' -d @kafka/connect-s3-sink.json
```

### Credenciais S3/MinIO

O conector referencia credenciais via `file:/opt/connector-s3.conf`. No
docker-compose do `kafka-connect`, monte este arquivo (ex.: secret do
Kubernetes ou `./secrets/connector-s3.conf`) com o formato:

```properties
aws_access_key_id=aurix
aws_secret_access_key=aurix_dev_password
```

## Restore (replay de tópicos)

1. Identifique o prefixo no bucket (`topics/aurix.pix/partition=0/...`).
2. Recrie os tópicos com a mesma configuração de partições/replicação.
3. Replay via **S3 source connector** (`io.confluent.connect.s3.S3SourceConnector`)
   apontando para o bucket com `topics.dir=topics`, ou reprocesse os arquivos
   JSON com o consumer do `aurix-data-pipelines` (Spark `read.json`).

```bash
# Exemplo de configuração mínima do source connector
curl -X POST http://localhost:8083/connectors -H 'Content-Type: application/json' -d '{
  "name": "aurix-s3-source-restore",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SourceConnector",
    "tasks.max": "1",
    "store.url": "http://minio:9000",
    "s3.bucket.name": "aurix-kafka-backups",
    "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
    "topics.dir": "topics",
    "s3.region": "us-east-1",
    "s3.path.style.access": "true"
  }
}'
```

## Notas

- O conector S3 sink exige o plugin `kafka-connect-s3` instalado em
  `/usr/share/confluent-hub-components` do `kafka-connect`
  (`confluent-hub install confluentinc/kafka-connect-s3:10.x`).
- A replicação cross-cluster (contínua) pode usar o `MirrorMaker 2` como
  alternativa ao snapshot; o S3 sink atende ao requisito de backup com replay.
