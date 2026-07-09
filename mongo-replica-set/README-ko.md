# MongoDB Replica Set (2대 서버, 3개 노드 + Arbiter)

> English version: [README.md](README.md)

이 문서는 2대의 물리 서버와 3개의 논리 노드(arbiter 포함)로 MongoDB Replica Set을 구성하는 방법을 설명합니다.

## 구조

- rs0
- mongo-a (Server A, Primary 후보)
- mongo-b (Server B, Secondary)
- mongo-arbiter (Server A, Arbiter)

## 주의

- 이 구성은 완전한 HA가 아닙니다.
- Server A가 죽으면 majority를 잃어서 write가 멈출 수 있습니다.
- 운영 환경에서는 물리 노드 3대 이상을 권장합니다.

## 서버 예시

- Server A: 192.168.0.10
- Server B: 192.168.0.11

## 공통 준비

```bash
mkdir -p ~/mongo-cluster
cd ~/mongo-cluster
```

## Keyfile 생성

```bash
openssl rand -base64 756 > mongo-keyfile
chmod 400 mongo-keyfile
```

Server B로 복사:

```bash
scp mongo-keyfile user@192.168.0.11:~/mongo-cluster/
```

## 중요

MongoDB root 사용자는 데이터 디렉터리가 비어 있을 때만 생성됩니다. 재실행하려면 데이터 디렉터리를 비우고 다시 시작해야 합니다.

## 시작

각 서버에서 `docker compose up -d`를 실행합니다.

## Replica Set 초기화

Server A에서 한 번만 실행합니다.

```bash
docker exec -it mongo-a mongosh -u root -p change-this-password --authenticationDatabase admin
```

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo-a:27017", priority: 2 },
    { _id: 1, host: "mongo-b:27017", priority: 1 },
    { _id: 2, host: "mongo-arbiter:27017", arbiterOnly: true }
  ]
})
```

## 연결 문자열

```text
mongodb://root:change-this-password@192.168.0.10:27017,192.168.0.11:27017/admin?replicaSet=rs0
```

## 참고

- Arbiter는 데이터는 저장하지 않고 투표만 합니다.
- Root 사용자는 처음 초기화할 때만 생성됩니다.
- 호스트 이름과 포트가 정확히 맞아야 Replica Set이 정상 동작합니다.
