# MongoDB Replica Set (2대 서버, 3개 노드 + Arbiter)

> English version: [README.md](README.md)

이 문서는 **2대의 물리 서버**와 **3개의 논리 노드(arbiter 포함)**를 사용해 MongoDB Replica Set을 구성하는 방법을 설명합니다. 인증도 함께 설정합니다.

---

## 구조

`rs0`

- `mongo-a` (Server A, Primary 후보)
- `mongo-b` (Server B, Secondary)
- `mongo-arbiter` (Server A, Arbiter)

---

## ⚠️ 중요 사항

- 이 구성은 완전한 HA를 제공하지 않습니다. 물리 서버는 2대뿐입니다.
- Server A가 장애를 일으키면 cluster가 majority를 잃어 write가 중단됩니다.
- 운영 환경에서는 물리 노드 3대 이상을 사용하는 것이 좋습니다.

---

## 서버 정보 예시

Server A: 192.168.0.10  
Server B: 192.168.0.11

실제 환경에 맞게 IP를 바꾸세요.

---

## 1. 공통 준비 (두 서버 모두)

```bash
mkdir -p ~/mongo-cluster
cd ~/mongo-cluster
```

---

## 2. Keyfile 설정(인증)

Server A에서 생성합니다.

```bash
openssl rand -base64 756 > mongo-keyfile
chmod 400 mongo-keyfile
```

Server B로 복사합니다.

```bash
scp mongo-keyfile user@192.168.0.11:~/mongo-cluster/
```

---

## 3. ⚠️ 깨끗한 시작이 필요합니다

MongoDB root 사용자는 데이터 디렉터리가 비어 있을 때만 생성됩니다.

다시 설정할 경우:

```bash
docker compose down -v
rm -rf mongo-a mongo-b mongo-arbiter
```

---

## 4. Server A docker-compose.yml

```yaml
services:
  mongo-a:
    image: mongo:8.2.7
    container_name: mongo-a
    restart: unless-stopped
    hostname: mongo-a
    ports:
      - "27017:27017"
    volumes:
      - ./mongo-a/data:/data/db
      - ./mongo-keyfile:/etc/mongo-keyfile:ro
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: change-this-password
    command:
      ["mongod","--replSet","rs0","--bind_ip_all","--keyFile","/etc/mongo-keyfile","--auth"]
    extra_hosts:
      - "mongo-a:192.168.0.10"
      - "mongo-b:192.168.0.11"
      - "mongo-arbiter:192.168.0.10"

  mongo-arbiter:
    image: mongo:8.2.7
    container_name: mongo-arbiter
    restart: unless-stopped
    hostname: mongo-arbiter
    ports:
      - "27018:27017"
    volumes:
      - ./mongo-arbiter/data:/data/db
      - ./mongo-keyfile:/etc/mongo-keyfile:ro
    command:
      ["mongod","--replSet","rs0","--bind_ip_all","--keyFile","/etc/mongo-keyfile","--auth"]
    extra_hosts:
      - "mongo-a:192.168.0.10"
      - "mongo-b:192.168.0.11"
      - "mongo-arbiter:192.168.0.10"
```

---

## 5. Server B docker-compose.yml

```yaml
services:
  mongo-b:
    image: mongo:7
    container_name: mongo-b
    restart: unless-stopped
    hostname: mongo-b
    ports:
      - "27017:27017"
    volumes:
      - ./mongo-b/data:/data/db
      - ./mongo-keyfile:/etc/mongo-keyfile:ro
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: change-this-password
    command:
      ["mongod","--replSet","rs0","--bind_ip_all","--keyFile","/etc/mongo-keyfile","--auth"]
    extra_hosts:
      - "mongo-a:192.168.0.10"
      - "mongo-b:192.168.0.11"
      - "mongo-arbiter:192.168.0.10"
```

---

## 6. 컨테이너 시작

두 서버 모두에서 실행합니다.

```bash
docker compose up -d
```

---

## 7. Replica Set 초기화

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

---

## 8. 상태 확인

```javascript
rs.status()
```

---

## 9. 연결 문자열

```text
mongodb://root:change-this-password@192.168.0.10:27017,192.168.0.11:27017/admin?replicaSet=rs0
```

---

## 10. 문제 해결

### 연결 문제

- 방화벽을 확인합니다(27017 포트가 열려 있어야 합니다).
- 서버 간 네트워크 연결을 확인합니다.
- `--bind_ip_all`이 설정되어 있는지 확인합니다.

### 인증 문제

- root 사용자는 처음 시작할 때만 생성됩니다.
- 자격 증명이 맞지 않으면 데이터 디렉터리를 초기화하세요.

### Replica Set 문제

- 호스트 이름이 일치하는지 확인합니다.
- `extra_hosts` 설정이 올바른지 확인합니다.
- 포트를 잘못 쓰지 않았는지 확인합니다. 내부적으로는 반드시 27017을 사용해야 합니다.

---

## 11. 요약

Server A:

- `mongo-a` (Primary)
- `mongo-arbiter`

Server B:

- `mongo-b` (Secondary)

---

## 마지막 조언

문제가 생기면 대부분 다음 중 하나입니다.

- 네트워크
- 방화벽
- 잘못된 호스트 이름

이것들 모두 아니라면, 축하합니다. 드문 문제를 찾은 것입니다.
