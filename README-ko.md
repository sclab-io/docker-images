# SCLAB Docker Images

> English version: [README.md](README.md)

## 빠른 참고

- **관리 주체**: [SCLAB](https://github.com/sclab-io/docker-images)
- **도움받는 곳**: [SCLAB Discord](https://discord.gg/KJqMvvR7dE) 또는 <support@sclab.io>
- **이슈 등록**: [https://github.com/sclab-io/docker-images/issues](https://github.com/sclab-io/docker-images/issues)
- **이 설명의 원본**: [docs 저장소의 `sclab/` 디렉터리](https://github.com/sclab-io/docker-images/blob/master/README.md) ([변경 이력](https://docs.sclab.io/docs/history/SCLAB%20Studio%20OnPremise))
- **개발 문서**: [docs.sclab.io](https://docs.sclab.io)

## SCLAB이란

SCLAB은 여러 데이터를 하나로 묶어 빠르게 시각화할 수 있게 해 주는 플랫폼입니다. 이 저장소는 그 플랫폼을 Docker 환경에서 설치하고 운영하는 데 필요한 이미지와 예시 구성을 제공합니다.

> [www.sclab.io](https://www.sclab.io/)

![logo](https://avatars.githubusercontent.com/u/84428855?s=200&v=4)

## 이 저장소의 이미지

### SCLAB 이미지 목록

- `sclabio/webapp`
- `sclabio/gis-process`
- `sclabio/mqtt-client`
- `sclabio/mqtt-broker`
- `sclabio/kafka-client`
- `sclabio/node-vm-service`
- `sclabio/ai-service`
- `sclabio/onpremise-tileserver` (지도 베이스맵 타일 서버, 지도 데이터 포함)
- `sclabio/vision-aio`
- `sclabio/vision-aio-gpu`
- `sclabio/vision-console`
- [`sclabio/sclab-agent`](https://hub.docker.com/r/sclabio/sclab-agent)

### SCLAB 이미지를 실행할 때 함께 쓰는 이미지

- [mongo](https://hub.docker.com/_/mongo)
- [bytemark/smtp](https://hub.docker.com/r/bytemark/smtp)
- [bitnami/redis](https://hub.docker.com/r/bitnami/redis)
- [qdrant/qdrant](https://hub.docker.com/r/qdrant/qdrant)
- [nginx](https://hub.docker.com/_/nginx)

## 설치

### 사전 요구 사항

#### 라이선스 코드

이 이미지를 사용하려면 LICENSE KEY가 필요합니다. 발급을 원하시면 support@sclab.io로 문의하세요.

#### AWS 자격 증명

SCLAB Docker 이미지를 내려받으려면 AWS 자격 증명이 필요합니다. 이 값은 라이선스 키와 함께 SCLAB 지원팀에서 제공됩니다. 설치 스크립트가 설정을 안내합니다.

#### 시스템 요구 사항

##### 하드웨어
- 메모리: 최소 8GB
- 저장 공간: 최소 40GB
- 아키텍처: x86_64 (AMD64)

##### 소프트웨어
- Linux OS
- sudo/root 권한
- 기본 Unix 도구들(없으면 자동 설치)
- Docker(없으면 자동 설치)
- AWS CLI(없으면 자동 설치)

#### 호환성

설치 스크립트는 대부분의 주요 Linux 배포판에서 동작합니다.

- Ubuntu/Debian 계열(Mint, Pop!_OS 등)
- RHEL/CentOS/Fedora 계열(Rocky Linux, AlmaLinux 등)
- SUSE/openSUSE 계열
- Arch Linux/Manjaro 계열
- Alpine Linux
- 그 외 다른 Linux 배포판

### 1단계. 파일 내려받기

```bash
git clone https://github.com/sclab-io/docker-images.git
cd docker-images
```

### 2단계. 설치 스크립트 실행

```bash
sudo ./install.sh
```

설치 스크립트가 하는 일:

1. 시스템 호환성과 요구 사항을 확인한다.
   - Docker가 없으면 사용자의 허용을 받아 자동 설치한다.
   - 부족한 의존성(curl, sed, grep)을 설치한다.
2. 설정 값을 입력받는다.
   - 라이선스 키(필수)
   - 데이터베이스 비밀번호(지정하지 않으면 자동 생성)
   - OpenAI / Gemini / DeepSeek API 키(선택, 비워 두면 로컬 Ollama 모델 사용)
   - editor를 별도 서브도메인으로 띄울 때 쓸 서브도메인 접두어(선택)
   - 도메인 이름(선택, 비워 두면 localhost)
   - 관리자 이메일과 비밀번호
3. 설정 파일을 갱신해 모든 서비스를 구성한다.
4. 보안 키를 생성한다(JWT 토큰, SSL 인증서).
5. AWS ECR에서 이미지를 받기 위한 AWS CLI를 설치한다.
6. AWS 자격 증명을 구성한다.
7. 서비스 간 통신용 Docker 네트워크를 만든다.

### 보안 참고

- 자동 생성된 비밀번호는 32자리 영숫자입니다.
- 관리자 비밀번호는 `settings.json`에 평문으로 저장됩니다.
- 첫 로그인 후에는 반드시 관리자 비밀번호를 바꾸세요.

### 문제 해결

문제가 생기면 아래를 확인하세요.

- `sudo ./install.sh`로 실행했는지 확인합니다.
- 필요하다면 실행 권한을 줍니다: `chmod +x install.sh`
- Docker가 제대로 설치되었는지 확인합니다: `docker --version`
- 패키지 관리자가 필요한 경우 설치 스크립트가 자동 감지해 적절한 것을 사용합니다.

## SCLAB Vision

이 저장소는 Vision 배포 방식을 두 가지로 제공합니다.

- `vision/`: 루트 SCLAB Studio 스택과 MongoDB / Redis / Qdrant를 공유하는 방식
- `vision-stand-alone/`: Vision만 독립적으로 실행하는 방식

자세한 설치 방법, 데이터 위치, 포트, 환경변수 설명은 각각 아래 문서를 참고하세요.

- [vision/README.md](vision/README.md)
- [vision-stand-alone/README.md](vision-stand-alone/README.md)

두 방식 모두 GPU 모드와 DVR 녹화를 지원합니다. 어떤 환경변수를 바꿔야 하는지, 기본값이 무엇인지, 각 값이 무슨 역할을 하는지는 하위 README에 자세히 적혀 있습니다.

### 파일 목록

| 파일 이름 | 설명 |
|:--|:--|
| `common.env` | 공통 환경 변수 |
| `webapp.env` | webapp용 환경 변수 |
| `gis-process.env` | GIS Process용 환경 변수 |
| `mqtt-client.env` | MQTT Client용 환경 변수 |
| `mqtt-broker.env` | MQTT Broker용 환경 변수 |
| `kafka-client.env` | Kafka Client용 환경 변수 |
| `ai-service.env` | AI service용 환경 변수 |
| `node-vm-service.env` | Node VM service용 환경 변수 |
| `db-agent.env` | SCLAB Agent용 환경 변수 |
| `tileserver.env` | 지도 타일 서버 edge 환경 변수 (허용 도메인, 캐시) |
| `tileserver/` | 지도 타일 서버 edge(`tileserver-edge`)용 Nginx 템플릿 |
| `tileserver/docker-compose.tileserver.yml` | 타일 서버 서비스 정의. 타일 서버를 설치할 때만 `docker-compose.yml` 에 추가됨 |
| `tileserver/enable.sh` | 타일 서버 서비스를 `docker-compose.yml` 에 추가하는 스크립트 (`install.sh` 가 사용, 나중에 직접 실행 가능) |
| `docker-compose.yml` | Docker Compose YAML |
| `gen.yml` | 키 생성을 위한 Docker Compose YAML |
| `nginx.conf` | Nginx 설정 |
| `_tls.sh` | 루트 `sclab-proxy`용 fallback TLS 인증서 생성 |
| `mongod.conf` | MongoDB 설정 |
| `settings.json` | SCLAB 설정 |
| `install.sh` | 설치 스크립트 |
| `run.sh` | 실행 스크립트 |
| `stop.sh` | 중지 스크립트 |
| `down.sh` | 컨테이너 정리 스크립트 |
| `logs.sh` | 로그 확인 스크립트 |
| `pull.sh` | 이미지 내려받기 스크립트 |
| `update.sh` | webapp 업데이트 스크립트 |
| `update-all.sh` | 전체 서비스 업데이트 스크립트 |
| `restart.sh` | 재시작 스크립트 |
| `up.sh` | `run.sh`의 대체 시작 스크립트 |
| `run.bat` | Windows 실행 스크립트 |
| `stop.bat` | Windows 중지 스크립트 |
| `down.bat` | Windows 정리 스크립트 |
| `logs.bat` | Windows 로그 스크립트 |
| `pull.bat` | Windows 이미지 다운로드 스크립트 |
| `update.bat` | Windows webapp 업데이트 스크립트 |
| `update-all.bat` | Windows 전체 업데이트 스크립트 |
| `restart.bat` | Windows 재시작 스크립트 |
| `vision/` | SCLAB Vision Docker Compose 배포 |
| `vision/install.sh` | Vision 단계별 설치 스크립트 |
| `vision/docker-compose.yml` | Vision compose 스택 (`vision-aio` + `vision-console`) |
| `vision/docker-compose.gpu.yml` | Vision GPU 오버레이 |
| `vision/.env.example` | Vision 환경 변수 예시 |
| `vision/up.sh` | Vision 시작 |
| `vision/down.sh` | Vision 중지 |
| `vision/logs.sh` | Vision 로그 확인 |
| `vision/pull.sh` | Vision 이미지 내려받기 |
| `vision/update.sh` | Vision 컨테이너 pull + 재생성 |
| `vision/restart.sh` | Vision 재시작 |
| `vision-stand-alone/` | 독립형 SCLAB Vision 배포 |
| `vision-stand-alone/install.sh` | 독립형 Vision 단계별 설치 스크립트 |
| `vision-stand-alone/docker-compose.yml` | 독립형 Vision compose 스택 (`mongo` + `redis` + `qdrant` + Vision + HTTPS proxy) |
| `vision-stand-alone/docker-compose.gpu.yml` | 독립형 Vision GPU 오버레이 |
| `vision-stand-alone/.env.example` | 독립형 Vision 환경 변수 예시 |
| `vision-stand-alone/up.sh` | 독립형 Vision 시작 |
| `vision-stand-alone/down.sh` | 독립형 Vision 중지 |
| `vision-stand-alone/logs.sh` | 독립형 Vision 로그 확인 |
| `vision-stand-alone/pull.sh` | 독립형 Vision 이미지 내려받기 |
| `vision-stand-alone/update.sh` | 독립형 Vision 컨테이너 pull + 재생성 |
| `vision-stand-alone/restart.sh` | 독립형 Vision 재시작 |

### common.env

| 변수 | 설명 |
|:--|:--|
| `ROOT_URL` | 도메인을 포함한 루트 URL |
| `HTTP_FORWARDED_COUNT` | 서비스 앞단에 있는 프록시 서버 수. 클라이언트 IP를 정확히 판별할 때 사용 |
| `LOG_PATH` | 로그 파일 경로. Docker 이미지 내부 경로이므로 보통 바꿀 필요 없음 |
| `LOG_LEVEL` | 로그 레벨(`[error, warn, info, debug]`) |
| `USE_FILE_LOG` | 파일 로그를 저장하지 않으려면 빈 값으로 둠 |
| `LOG_FILE_COUNT` | 하루 단위 로그 파일 보관 개수(예: 31이면 31일 보관) |
| `PORT` | 서비스 기본 포트. 실제 포트 변경은 `docker-compose.yml`에서 조정 |
| `NODE_ENV` | Node.js 실행 환경 변수 |
| `MONGO_URL` | MongoDB 접속 문자열 |
| `MONGO_DB_READ_PREFERENCE` | MongoDB 읽기 선호도 |
| `MONGO_DB_POOL_SIZE` | MongoDB 연결 풀 크기 |
| `METEORD_NODE_OPTIONS` | Node.js 실행 옵션 |
| `MAIL_URL` | 메일 서버(SMTP) 접속 URL |
| `QDRANT_CLUSTER_URL` | Qdrant 벡터 DB 클러스터 URL |
| `QDRANT_API_KEY` | Qdrant API 키 |
| `VECTOR_DB_PROVIDER` | 기본 벡터 DB 제공자. `qdrant|opensearch|elasticsearch|pinecone|weaviate|milvus|chroma|pgvector` 중 하나 |
| `VECTOR_DB_ENCRYPTION_KEY` | 관리 UI에 저장된 벡터 DB 자격 증명을 암호화하는 AES-256-GCM 키. 운영에서는 반드시 설정하고 webapp과 ai-service가 동일하게 사용해야 함 |
| `OPENSEARCH_ENDPOINT` | OpenSearch 엔드포인트 URL |
| `OPENSEARCH_USERNAME` | OpenSearch 사용자 이름. AOSS에서는 AWS Access Key ID |
| `OPENSEARCH_PASSWORD` | OpenSearch 비밀번호. AOSS에서는 AWS Secret Access Key |
| `ELASTICSEARCH_NODE` | Elasticsearch 노드 URL |
| `ELASTICSEARCH_API_KEY` | Elasticsearch API 키 |
| `ELASTICSEARCH_USERNAME` | Elasticsearch 사용자 이름 |
| `ELASTICSEARCH_PASSWORD` | Elasticsearch 비밀번호 |
| `PINECONE_API_KEY` | Pinecone API 키 |
| `PINECONE_HOST` | Pinecone 인덱스 호스트 URL |
| `WEAVIATE_URL` | Weaviate URL |
| `WEAVIATE_API_KEY` | Weaviate API 키 |
| `MILVUS_HOST` | Milvus 호스트 |
| `MILVUS_PORT` | Milvus 포트 |
| `MILVUS_USERNAME` | Milvus 사용자 이름(선택) |
| `MILVUS_PASSWORD` | Milvus 비밀번호(선택) |
| `MILVUS_DB_NAME` | Milvus 데이터베이스 이름 |
| `CHROMA_URL` | Chroma URL |
| `CHROMA_API_KEY` | Chroma API 키 |
| `CHROMA_DATABASE` | Chroma 데이터베이스 이름 |
| `PGVECTOR_URL` | PostgreSQL/pgvector 연결 문자열 |
| `OPENAI_KEY` | OpenAI API 키 |
| `GEMINI_API_KEY` | Gemini API 키 |
| `OLLAMA_API_HOST` | Ollama API 호스트 URL |
| `VLLM_API_HOST` | vLLM API 호스트 URL |
| `VLLM_API_KEY` | vLLM API 키 |
| `DEEPSEEK_API_KEY` | DeepSeek API 키 |

### webapp.env

| 변수 | 설명 |
|:--|:--|
| `SERVER_ID` | 여러 서버를 구분할 때 쓰는 ID |
| `ADD_INDEX` | MongoDB 인덱스 생성 여부(`1`이면 생성) |
| `IOT_JWT_KEY` | IoT JWT 개인키 파일 경로 |
| `IOT_JWT_PUB_KEY` | IoT JWT 공개키 파일 경로 |
| `API_JWT_KEY` | API JWT 개인키 파일 경로 |
| `API_JWT_PUB_KEY` | API JWT 공개키 파일 경로 |
| `SERVER_FILE_URL` | 서버 측 파일 읽기 경로 |
| `AUTO_PHOTO_SERVICE_INTERVAL` | 사진 서비스 간격(초) |
| `TRANSCRIPTIONS_API_HOST` | 전사 API 호스트. 기본값은 `https://api.openai.com` |
| `TRANSCRIPTIONS_MODEL` | 전사 모델. 기본값은 `whisper-1` |

### gis-process.env

| 변수 | 설명 |
|:--|:--|
| `SERVER_ID` | GIS 파일을 파싱해 DB에 저장할 때 쓰는 서버 ID |
| `SERVER_FILE_URL` | 서버 측 파일 읽기 경로 |

### mqtt-client.env

| 변수 | 설명 |
|:--|:--|
| `SERVER_NAME` | MQTT 클라이언트 서버 이름 |
| `SERVER_DOMAIN` | MQTT 클라이언트 서버 도메인 |
| `SERVER_REGION` | MQTT 클라이언트 서버 리전 |
| `PUBLIC_IP` | 공인 IP 주소 |
| `PRIVATE_IP` | 사설 IP 주소 |

### mqtt-broker.env

| 변수 | 설명 |
|:--|:--|
| `SERVER_NAME` | MQTT broker 서버 이름 |
| `SERVER_DOMAIN` | MQTT broker 서버 도메인 |
| `SERVER_REGION` | MQTT broker 서버 리전 |
| `PUBLIC_IP` | 공인 IP 주소 |
| `PRIVATE_IP` | 사설 IP 주소 |
| `JWT_KEY` | MQTT JWT 키 파일 경로(RS256) |
| `TLS_CERT` | SSL 인증서 파일 경로 |
| `TLS_PRIVATE_KEY` | SSL 개인키 파일 경로 |

### kafka-client.env

| 변수 | 설명 |
|:--|:--|
| `SERVER_NAME` | Kafka 클라이언트 서버 이름 |
| `SERVER_DOMAIN` | Kafka 클라이언트 서버 도메인 |
| `SERVER_REGION` | Kafka 클라이언트 서버 리전 |
| `PUBLIC_IP` | 공인 IP 주소 |
| `PRIVATE_IP` | 사설 IP 주소 |

### ai-service.env

| 변수 | 설명 |
|:--|:--|
| `REDIS_URL` | Redis 서버 URL |
| `AI_SERVER_ID` | HA용 AI Service ID |
| `USE_AI_SERVICE` | AI Service 실행 여부(`1` 또는 빈 값) |
| `IS_SYNC_SERVER` | 데이터 동기화 서버 여부(여러 대 중 한 대만 `1`) |
| `USE_CHAT_SERVICE` | AI Chat Service 여부 |
| `USE_SQL_GEN_SERVICE` | 통합 데이터용 SQL 생성기 여부 |
| `USE_AGENT_SERVICE` | AI Agent Service 여부 |
| `USE_AGENT_SERVICE_SCHEDULER` | AI Agent Service Scheduler 여부 |
| `USE_MCP_SERVICE` | MCP Service 여부 |
| `SERVER_FILE_URL` | 서버 측 파일 읽기 경로 |
| `NODE_OPTIONS` | Node.js 옵션 |
| `ORIGIN` | CORS origin |
| `CREDENTIALS` | credentials 허용 여부(`true` 또는 빈 값) |
| `PORT` | AI Service REST API 포트 |
| `NODE_ENV` | Node.js 환경 |
| `HIDE_JSON` | 채팅 메시지에서 JSON 숨김 여부 |
| `CODE_EXECUTOR_TYPE` | `node-vm` 또는 `daytona` |
| `CODE_EXECUTOR_API_URL` | CODE EXECUTOR API URL |
| `CODE_EXECUTOR_API_KEY` | CODE EXECUTOR API 키 |
| `JWT_PUBLIC_KEY_PATH` | API JWT 공개키 파일 경로 |

### node-vm-service.env

| 변수 | 설명 |
|:--|:--|
| `LOG_DIR` | 로그 경로 |
| `PORT` | node-vm-service 포트 |
| `NODE_ENV` | Node.js 환경 |
| `LOG_LEVEL` | 로그 레벨 |
| `ISOLATED_VM_TIMEOUT` | 타임아웃(초) |
| `ISOLATED_VM_MAX_MEMORY` | 최대 메모리(MB) |

### db-agent.env

| 변수 | 설명 |
|:--|:--|
| `LOG_DIR` | 로그 경로 |
| `PORT` | SCLAB Agent 포트 |
| `NODE_ENV` | Node.js 환경 |
| `LOG_LEVEL` | 로그 레벨 |
| `SECRET_KEY` | 비밀 키 |
| `JWT_PRIVATE_KEY_PATH` | JWT 개인키 경로 |
| `JWT_PUBLIC_KEY_PATH` | JWT 공개키 경로 |
| `TLS_CERT` | SSL 공개 인증서 경로 |
| `TLS_KEY` | SSL 개인키 경로 |
| `AGENT_DB_PATH` | Agent 데이터베이스 파일 경로 |
| `USE_MYBATIS` | mybatis mapper 사용 여부 |
| `ORACLE_CLIENT_DIR` | Oracle Client 디렉터리 |
| `MSSQL_IDLE_TIMEOUT_MS` | SQL Server 유휴 타임아웃(ms) |
| `TUNNEL_KEEP_ALIVE_INTERVAL_MS` | SSH tunnel keep-alive 간격(ms) |

### tileserver.env

지도 위젯의 베이스맵(Positron / Dark Matter / Voyager 스타일)은 공개 CARTO 서비스 대신 자체 타일 서버에서 가져옵니다.
CARTO 는 API 키 없는 요청에 워터마크를 찍기 때문입니다.

| 변수 | 설명 |
|:--|:--|
| `TILESERVER_ALLOWED_REFERERS` | 타일을 가져다 쓸 수 있는 도메인 목록 (공백 구분, nginx `valid_referers` 문법). `install.sh` 가 `sclab-onprem` 을 사용자 도메인으로 바꿉니다. Referer 가 없거나 목록 밖 도메인이면 403 입니다. |
| `TILESERVER_AUTH_URL` | 목록에 없는 도메인을 webapp 에 물어보는 주소 (`http://webapp:80/tile-auth`). webapp 은 사이트 도메인, 발행 사이트의 커스텀 도메인, **관리자 > 타일 서버** 에 등록한 도메인을 허용합니다. |
| `TILESERVER_AUTH_CACHE_TTL` | webapp 응답을 도메인별로 캐시하는 시간 (기본 `10m`) |
| `TILESERVER_CACHE_SIZE` | 렌더링된 타일 디스크 캐시 크기 (`./data/tileserver/cache`, 기본 `5g`) |
| `TILESERVER_CACHE_TTL` | 렌더링된 타일을 캐시에 두는 기간 (기본 `30d`) |
| `NGINX_PORT` / `TILESERVER_UPSTREAM` | 내부 연결용, 바꾸지 마세요 |

#### 지도 타일 서버

타일 서버는 선택 사항이며 서비스 정의가 기본 `docker-compose.yml` 에 **들어 있지 않습니다**(이미지가 약 30GB). `install.sh` 가
**Install the map tile server? [y/N]** 를 묻고(기본: 설치 안 함), 설치를 선택하면 타일 서버 주소(`public.tileServerURL`, 기본
`https://<도메인>/tiles`)와 허용 도메인(`TILESERVER_ALLOWED_REFERERS`, 기본 `<도메인> *.<도메인>`)을 물어본 뒤
`tileserver/docker-compose.tileserver.yml` 의 `tileserver`, `tileserver-edge` 서비스를 `docker-compose.yml` 에 추가합니다.

설치 후에 추가하려면 `./tileserver/enable.sh` 를 실행하고 `settings.json` 의 `public.tileServerURL` 과 `tileserver.env` 의
`TILESERVER_ALLOWED_REFERERS` 를 채운 뒤 `./run.sh` 를 실행합니다. 제거하려면 `docker compose down tileserver tileserver-edge` 후
`docker-compose.yml` 에서 두 서비스를 지우고 `public.tileServerURL` 을 비웁니다.

- `tileserver`(이미지 `sclabio/onpremise-tileserver`)가 타일을 렌더링합니다. 이미지에 스타일·폰트·벡터 지도 데이터가 들어 있어
  인터넷 연결 없이 동작합니다. 데이터는 전 세계 개요(약 z11~12 까지) + 대한민국 상세(z14) 이며, 한국 밖은 그 줌 이상으로 확대해도
  더 자세해지지 않습니다. 이미지 크기는 약 30GB 입니다.
- `tileserver-edge`(nginx)가 Referer 도메인을 검사하고 렌더링된 타일을 캐시합니다. `sclab-proxy` 가 `https://<도메인>/tiles/` 를 이쪽으로
  넘기고, `settings.json` 의 `public.tileServerURL` 이 지도 위젯을 그 주소로 보냅니다.
- 다른 도메인(예: 발행 사이트를 임베드하는 고객사 포털)을 허용하려면 `TILESERVER_ALLOWED_REFERERS` 에 추가하고 `tileserver-edge` 를
  재시작하거나, **관리자 > 타일 서버** 에 등록합니다(재시작 불필요).
- 다른 지역의 지도 데이터가 필요하면 SCLAB 소스의 `src/tileserver` 에서 `scripts/build-data.sh <지역>` 으로 `tiles.mbtiles` 를 만든 뒤
  `tileserver` 서비스에 `- ./data/tileserver/tiles.mbtiles:/data/data/tiles.mbtiles:ro` 로 마운트해 덮어씁니다.
  데이터 범위 밖은 빈 배경으로 렌더링됩니다.
- `public.tileServerURL` 을 빈 문자열로 두면 지도 위젯이 공개 CARTO 타일(워터마크)로 돌아갑니다.

### settings.json

`settings.json`에는 공개 설정과 비공개 설정이 함께 들어 있습니다. 대표적인 항목은 아래와 같습니다.

| 변수 | 설명 |
|:--|:--|
| `public` | 클라이언트와 서버가 모두 접근할 수 있는 공개 설정 |
| `public.siteName` | 사이트 이름 |
| `public.staticFilePath` | 정적 파일 경로 |
| `public.supportName` | 이메일 지원 담당자 이름 |
| `public.supportEmail` | 지원 이메일 주소 |
| `public.siteDomain` | 사이트 도메인 |
| `public.tileServerURL` | 지도 타일 서버 기본 URL (지도 위젯의 베이스맵). `install.sh` 가 타일 서버 설치 여부를 묻고 채웁니다(기본 `https://<도메인>/tiles`, `sclab-proxy` 가 `tileserver-edge` 로 넘김). 비어 있으면(기본) 공개 CARTO 타일을 쓰며 "API KEY REQUIRED" 워터마크가 찍힙니다. 아래 "지도 타일 서버" 참고. |
| `public.mainPrefix` | 메인 prefix가 따로 있을 때 사용. 예: `app.sclab.io` |
| `public.sso` | 사용할 SSO 목록(google, facebook, kakao, naver) |
| `public.ldap.enabled` | 로그인 페이지에 LDAP 로그인 폼을 표시할지 여부 |
| `public.useForceSSL` | HTTP를 HTTPS로 강제 리다이렉트할지 여부 |
| `public.uploadMaxMB` | 최대 업로드 파일 크기(MB) |
| `public.editorHosts` | editor host 배열 |
| `public.ai.chat` | AI chat 기본 프롬프트 |
| `public.ai.openai.llm` | OpenAI LLM 목록 |
| `public.ai.openai.embed` | OpenAI embedding model 목록 |
| `public.ai.gemini.llm` | Gemini LLM 목록 |
| `public.ai.gemini.embed` | Gemini embedding model 목록 |
| `public.ai.ollama.llm` | Ollama LLM 목록 |
| `public.ai.ollama.embed` | Ollama embedding model 목록 |
| `public.ai.vllm.llm` | vLLM LLM 목록 |
| `public.ai.vllm.embed` | vLLM embedding model 목록 |
| `public.ai.deepseek.llm` | DeepSeek LLM 목록 |
| `public.ai.*.llm[].contextLimit` | **선택.** 이 배포에서 그 모델에 허용할 입력 토큰 수. 모델 자체의 최대치는 하드웨어와 무관하므로, 실제 GPU가 감당하는 값을 지정한다. 생략하면 모델 최대치를 사용한다. 아래 "모델 컨텍스트 한도" 참고 |
| `public.ai.ocrModels` | OCR용 VLM 모델 목록 |
| `public.ai.sqlModel` | SQL 생성용 모델 |
| `public.hub.llmAPI` | `"openai"`(기본), `"gemini"`, `"ollama"` |
| `private.adminEmail` | 관리자 이메일 주소 |
| `private.adminPassword` | 관리자 비밀번호 |
| `private.license` | SCLAB 온프레미스 라이선스 코드 |
| `private.sso.google.clientId` | Google OAuth client ID |
| `private.sso.google.secret` | Google OAuth secret |
| `private.sso.naver.clientId` | Naver OAuth client ID |
| `private.sso.naver.secret` | Naver OAuth secret |
| `private.sso.kakao.clientId` | Kakao OAuth client ID |
| `private.sso.kakao.secret` | Kakao OAuth secret |
| `private.sso.facebook.clientId` | Facebook OAuth client ID |
| `private.sso.facebook.secret` | Facebook OAuth secret |
| `private.sso.ldap.url` | LDAP 서버 URL |
| `private.sso.ldap.port` | LDAP 포트 |
| `private.sso.ldap.dn` | direct-bind DN 템플릿 |
| `private.sso.ldap.searchDN` | search-then-bind용 서비스 계정 DN |
| `private.sso.ldap.searchCredentials` | searchDN용 비밀번호 |
| `private.sso.ldap.base` | 검색 base DN |
| `private.sso.ldap.searchFilter` | 사용자 검색 필터 |
| `private.sso.ldap.defaultDomain` | mail 속성이 없을 때 덧붙일 기본 도메인 |
| `private.sso.ldap.createNewUser` | 첫 로그인 성공 시 자동으로 SCLAB 사용자 생성 여부 |
| `private.cors` | CORS 헤더(`Access-Control-Allow-Origin`) |
| `redisOplog` | 서버에서만 사용하는 Redis 연결 정보 |
| `redisOplog.redis.port` | Redis 포트 |
| `redisOplog.redis.host` | Redis 호스트 |
| `redisOplog.redis.password` | Redis 비밀번호 |
| `redisOplog.retryIntervalMs` | Redis 재연결 간격(ms) |
| `redisOplog.mutationDefaults.optimistic` | diff를 동기 처리하지 않고 client-side mutation과 함께 동작 |
| `redisOplog.mutationDefaults.pushToRedis` | 기본적으로 변경 내용을 Redis에 푸시할지 여부 |
| `redisOplog.debug` | redis-oplog의 타임스탬프와 동작을 표시할지 여부 |

#### 모델 컨텍스트 한도

모델의 최대 컨텍스트 길이는 **모델의 속성**이지 하드웨어의 속성이 아닙니다.
같은 모델이라도 32&nbsp;GB GPU에서 감당할 수 있는 컨텍스트는 96&nbsp;GB GPU보다 훨씬 작으므로,
온프레미스 설치에서는 "이 장비가 실제로 감당하는 값"을 따로 지정할 수 있어야 합니다.

넓은 것부터 좁은 것 순으로 3계층입니다.

| 계층 | 위치 | 의미 |
|:--|:--|:--|
| 모델 최대치 | SCLAB 내장 | 모델 자체가 지원하는 최대 컨텍스트. 아래 두 값이 없을 때 사용됩니다. |
| 배포 한도 | `settings.json` → `public.ai.*.llm[].contextLimit` | 이 모델을 서빙하는 GPU가 감당하는 값. 해당 모델을 선택한 모든 AI에 적용됩니다. |
| AI별 재정의 | 에디터 → AI 설정 → **입력 컨텍스트 제한** | 체크박스와 토큰 수 입력. 개별 AI 데이터에서 배포 한도를 덮어씁니다. |

한도를 넘는 프롬프트는 요청을 보내기 전에 잘리므로, 값을 크게 잡아도 그 자리에서
드러나지 않고 서빙 백엔드가 요청을 거부하는 형태로 나타납니다.
백엔드에 실제로 설정한 값과 맞추세요.

* **Ollama** — 모델을 서빙할 때 지정한 `num_ctx`
* **vLLM** — 서버 기동 시 지정한 `--max-model-len`

##### 용량 산정

가장 큰 비용은 KV 캐시이며 컨텍스트 길이에 비례해 커집니다.

```
KV 바이트 = 컨텍스트 토큰 수
          x 어텐션 레이어 수 x KV 헤드 수 x head_dim x 2 (K, V)
          x 요소당 바이트 (FP8은 1, FP16/BF16은 2)
```

여기에 모델 가중치와 활성화용 1~2&nbsp;GB 정도를 더하면 필요한 VRAM이 나옵니다.
하이브리드 어텐션이나 sliding-window 계열 모델은 **full-attention 레이어만** 세면 되므로,
전체 레이어 수만 보고 계산하면 크게 과대평가하게 됩니다.

백엔드에서 *context length exceeded* 오류가 나면, 백엔드의 한도를 GPU가 감당하는 수준
이상으로 올리지 말고 `contextLimit`(또는 AI별 재정의)을 낮추세요. 전자는 명확한 거부를
메모리 부족 크래시로 바꿔놓을 뿐입니다.

#### LDAP 로그인

SCLAB Studio는 기본 ID/비밀번호 로그인 외에도 회사 LDAP 서버로 인증할 수 있습니다. 이 기능을 켜면 로그인 페이지에 LDAP 폼이 표시되고, 처음 성공한 로그인 시 사용자 계정이 SCLAB에 자동 생성됩니다(`createNewUser`). 브라우저에서는 사용자 이름/비밀번호만 전송되며, 연결 정보는 모두 서버에 남습니다.

`public.ldap.enabled`로 폼을 켜고, `private.sso.ldap` 아래에서 서버를 설정하세요.

**예시**(direct bind):

```json
"public": { "ldap": { "enabled": true } },
"private": {
  "sso": {
    "ldap": {
      "url": "ldap://ldap.example.com",
      "port": "389",
      "dn": "uid=#{username},ou=people,dc=example,dc=com",
      "base": "dc=example,dc=com",
      "searchFilter": "(uid=#{username})",
      "defaultDomain": "example.com",
      "createNewUser": true
    }
  }
}
```

> `ldaps://`를 쓸 경우 포트를 `636`으로 맞추세요. 서버 인증서가 공인 CA 발급이 아니라면, `private.sso.ldap.ldapsCertificate`에 CA 인증서(PEM 문자열)를 넣어야 합니다.

## SCLAB Studio 실행

### 빠른 명령 참고

| 스크립트 | 설명 | 사용 예 |
|:--|:--|:--|
| `install.sh` | 초기 설치 및 구성 | `sudo ./install.sh` |
| `run.sh` | 모든 서비스 시작 | `sudo ./run.sh` |
| `stop.sh` | 모든 서비스 중지(데이터 보존) | `sudo ./stop.sh` |
| `restart.sh` | 모든 서비스 재시작 | `sudo ./restart.sh` |
| `logs.sh` | 실시간 로그 확인 | `sudo ./logs.sh` |
| `down.sh` | 컨테이너 중지 및 삭제 | `sudo ./down.sh` |
| `up.sh` | 시작 대체 명령 | `sudo ./up.sh` |
| `pull.sh` | 최신 이미지 받기 | `sudo ./pull.sh` |
| `update.sh` | webapp만 업데이트 | `sudo ./update.sh` |
| `update-all.sh` | 모든 서비스 업데이트 | `sudo ./update-all.sh` |

### 서비스 시작

```bash
sudo ./run.sh
```

### SCLAB Studio 접속

실행 후 다음 주소로 접속할 수 있습니다.

- 로컬 개발: `https://127.0.0.1`
- 운영 환경: `https://sclab-onprem` 또는 설정한 도메인
- editor(메인 prefix가 설정된 경우): `https://editor.sclab-onprem`

### 로그인

설치가 끝날 때 표시된 관리자 계정을 사용합니다.

- 이메일: 설치 시 입력한 이메일(기본값: `admin@sclab.io`)
- 비밀번호: 직접 지정한 값 또는 자동 생성된 값

**주의**: 첫 로그인 후에는 관리자 인터페이스에서 비밀번호를 바로 바꾸세요.

## SCLAB Studio 관리

### 서비스 중지

```bash
sudo ./stop.sh
```

실행 중인 모든 컨테이너를 중지하지만 데이터는 유지합니다.

### 서비스 재시작

```bash
sudo ./restart.sh
```

모든 서비스를 다시 시작합니다(`stop.sh` 후 `run.sh`와 동일).

### 로그 보기

```bash
sudo ./logs.sh
```

모든 서비스의 실시간 로그를 보여 줍니다. `Ctrl+C`로 종료할 수 있습니다.

### 완전 종료

```bash
sudo ./down.sh
```

모든 컨테이너를 중지하고 삭제하지만 데이터 볼륨은 유지합니다.

### 대체 시작

```bash
sudo ./up.sh
```

`run.sh`의 대체 명령입니다. 백그라운드로 시작합니다.

## SCLAB Studio 업데이트

### 최신 이미지 받기

```bash
sudo ./pull.sh
```

서비스를 중지하지 않고 모든 SCLAB Studio 이미지를 최신으로 받습니다.

### webapp만 업데이트

```bash
sudo ./update.sh
```

webapp 서비스만 업데이트합니다.

1. 최신 webapp 이미지를 받습니다.
2. webapp 컨테이너를 중지합니다.
3. 새 이미지로 다시 시작합니다.

다른 서비스는 건드리지 않고 webapp만 빨리 업데이트할 때 사용합니다.

### 모든 서비스 업데이트

```bash
sudo ./update-all.sh
```

모든 SCLAB Studio 서비스를 업데이트합니다.

1. 모든 최신 이미지를 받습니다.
2. 모든 서비스를 중지합니다.
3. 새 이미지로 다시 시작합니다.

여러 서비스가 함께 바뀌었거나 큰 버전 업그레이드를 할 때 사용합니다.

## db agent API token 확인

```bash
sudo docker logs sclab-agent
```

## ollama 설치

[Ollama Install](./ollama/README.md)

## 시스템 다이어그램

![System Diagram](./img/System-Diagram.png)

## Google SMTP 사용 방법

- 앱 비밀번호를 만듭니다.
- [https://myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
- `common.env` 파일의 `MAIL_URL` 환경 변수를 다음처럼 바꿉니다.
- `MAIL_URL=smtps://[GMAIL_ID]:[APP_PASSWORD]@smtp.gmail.com:465`
- 예시: `MAIL_URL=smtps://yourname@gmail.com:abcdwxyz1234pqrs@smtp.gmail.com:465`
- `settings.json`의 `public.supportEmail` 값을 다음처럼 바꿉니다.
- `supportEmail: "yourname@gmail.com"`
- 다시 시작합니다: `sudo ./restart.sh`

## 라이선스

Copyright (c) 2023 SCLAB All rights reserved.
