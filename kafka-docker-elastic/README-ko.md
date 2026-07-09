# Kafka Docker Elastic 설정

```bash
mkdir -p ./data/kafka-connect/plugins
cp ./elastic-source-connect-1.5.2-jar-with-dependencies.jar ./data/kafka-connect/plugins
docker compose up
```

백그라운드로 실행하려면:

```bash
docker compose up -d
```
