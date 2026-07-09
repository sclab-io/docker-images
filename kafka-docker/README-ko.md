# Kafka Docker 시작

> English version: [README.md](README.md)

이 예시는 Kafka, ksqlDB, 관련 도구를 Docker Compose로 실행하는 방법을 보여 줍니다. 먼저 필요한 폴더를 만들고, 그 다음 Compose를 시작하면 됩니다.

시작하기 전에 `setup.sh`를 실행해서 `data` 폴더를 만들어 주세요.

```bash
./setup.sh
```

서비스 시작:

```bash
docker compose up -d
```

ksql CLI:

```bash
docker exec -it ksqldb-cli ksql http://ksqldb-server:8088
```

로그 확인:

```bash
docker compose logs -f
```

샘플 스트림과 참고 링크는 `README.md`를 보세요.

## 참고

- `setup.sh`는 초기 데이터 디렉터리를 준비합니다.
- `ksqldb-cli`는 Kafka 토픽을 SQL처럼 다루는 데 사용합니다.
- 샘플 스트림은 중첩 JSON을 다루는 방법을 보여 줍니다.
