# Kafka Docker 시작

> English version: [README.md](README.md)

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

로그 보기:

```bash
docker compose logs -f
```

스트림 샘플:

```sql
create stream products_stream (
  payload STRUCT<
		after STRUCT<
			id INT,
      name VARCHAR,
      description VARCHAR,
      weight DOUBLE
		>
	>
) with (kafka_topic='mysqluserdb.inventory.products', value_format='json', partitions=1);

create stream products_where as 
select payload->after->id as id, payload->after->name as name, payload->after->weight as weight from products_stream
where payload->after->weight > 100 emit changes;
```

참고:

- https://ksqldb.io
- https://developer.confluent.io/tutorials/working-with-nested-json/ksql.html
