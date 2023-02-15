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
