# Kafka Docker Elastic 설정

> English version: [README.md](README.md)

이 예시는 Kafka Connect에 Elasticsearch 관련 커넥터 JAR를 넣고 실행하는 간단한 준비 절차입니다.

```bash
mkdir -p ./data/kafka-connect/plugins
cp ./elastic-source-connect-1.5.2-jar-with-dependencies.jar ./data/kafka-connect/plugins
docker compose up
```

백그라운드로 실행하려면:

```bash
docker compose up -d
```

## 참고

- 플러그인 JAR는 `data/kafka-connect/plugins`에 넣습니다.
- `docker compose up -d`는 개발 중 백그라운드 실행에 편합니다.
