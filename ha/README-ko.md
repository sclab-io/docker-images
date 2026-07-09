# SCLAB HA

## 설명

이 예시는 HA 구성을 보여 줍니다. 2대의 Ubuntu 서버에 설치할 수 있습니다. 예시에서는 모든 서비스를 서버 1에 설치하고, 웹앱 10개 인스턴스를 서버 2에 띄웁니다. 실제 운영에서는 MongoDB, Redis, Qdrant를 Managed Service로 사용하는 것이 좋습니다. 이 예시에는 LoadBalancer가 포함되어 있지 않으므로 ALB, ELB, L4 스위치 같은 장비를 앞단에 두어야 합니다.

## 방화벽 포트

| 포트 | 서비스 |
|---|---|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |
| 27017 | MongoDB |
| 6379 | Redis |
| 6333 | Qdrant |
| 8883 | MQTT |
| 8888 | MQTT over WebSocket |
| 7890 | SCLAB Agent (HTTPS) |
| 2049 | NFS |

## 설치

- [Master](./master/README.md)
- [Slave](./slave/README.md)
