# before start, create data folders using setup.sh
```bash
./setup.sh
```
# start
```bash
docker compose up -d
```
# ksql cli 
```bash
docker exec -it ksqldb-cli ksql http://ksqldb-server:8088
```
# logs
```bash
docker compose logs -f
```
# stream sample
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
where payload->after->weight > 100;
```
# reference
- https://ksqldb.io
- https://developer.confluent.io/tutorials/working-with-nested-json/ksql.html
