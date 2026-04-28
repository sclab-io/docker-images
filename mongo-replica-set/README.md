# MongoDB Replica Set (2 Servers, 3 Nodes with Arbiter)

This guide explains how to set up a MongoDB Replica Set using **2 physical servers** and **3 logical nodes (including an arbiter)** with proper authentication.

---

## Architecture

rs0
- mongo-a (Server A, Primary candidate)
- mongo-b (Server B, Secondary)
- mongo-arbiter (Server A, Arbiter)

---

## ⚠️ Important Notes

- This setup does NOT provide full HA (only 2 physical servers)
- If Server A fails → cluster loses majority → writes stop
- Production environments should use 3+ physical nodes

---

## Server Info (Example)

Server A: 192.168.0.10  
Server B: 192.168.0.11  

Replace with your actual IPs.

---

## 1. Common Setup (Both Servers)

```bash
mkdir -p ~/mongo-cluster
cd ~/mongo-cluster
```

---

## 2. Keyfile Setup (Authentication)

Generate on Server A:

```bash
openssl rand -base64 756 > mongo-keyfile
chmod 400 mongo-keyfile
```

Copy to Server B:

```bash
scp mongo-keyfile user@192.168.0.11:~/mongo-cluster/
```

---

## 3. ⚠️ Clean Start Requirement

MongoDB root user is created ONLY when data directory is empty.

If re-running setup:

```bash
docker compose down -v
rm -rf mongo-a mongo-b mongo-arbiter
```

---

## 4. Server A docker-compose.yml

```yaml
services:
  mongo-a:
    image: mongo:7
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
    image: mongo:7
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

## 6. Start Containers

Run on BOTH servers:

```bash
docker compose up -d
```

---

## 7. Initialize Replica Set (Run ONLY ONCE on Server A)

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

## 8. Verify Status

```javascript
rs.status()
```

---

## 9. Connection String

```
mongodb://root:change-this-password@192.168.0.10:27017,192.168.0.11:27017/admin?replicaSet=rs0
```

---

## 10. Troubleshooting

### Connection Issues
- Check firewall (port 27017 open)
- Check network connectivity between servers
- Ensure `--bind_ip_all` is set

### Authentication Issues
- Root user only created on first startup
- If credentials fail → reset data directories

### Replica Set Issues
- Hostname mismatch
- extra_hosts misconfiguration
- Wrong port (must use 27017 internally)

---

## 11. Summary

Server A:
- mongo-a (Primary)
- mongo-arbiter

Server B:
- mongo-b (Secondary)

---

## Final Advice

If this breaks, it’s usually:
- Network
- Firewall
- Wrong hostname

If it's none of those, congratulations—you found something rare.
