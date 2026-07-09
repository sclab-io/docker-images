# Kafka Docker 시작

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
