# Kafka Docker Elastic 설정

> English version: [README.md](README.md)

Kafka Connect에 Elasticsearch 관련 커넥터를 넣고 실행하기 위한 간단한 설정입니다.

## 준비

```bash
mkdir -p ./data/kafka-connect/plugins
cp ./elastic-source-connect-1.5.2-jar-with-dependencies.jar ./data/kafka-connect/plugins
```

## 실행

기본 실행:

```bash
docker compose up
```

백그라운드 실행:

```bash
docker compose up -d
```

## 참고

- 커넥터 JAR는 `./data/kafka-connect/plugins`에 넣어야 합니다.
- 개발 중에는 `docker compose up -d`로 백그라운드 실행하면 편합니다.
