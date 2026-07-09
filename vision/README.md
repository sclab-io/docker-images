# SCLAB Vision Docker Deployment

이 폴더는 SCLAB Studio의 루트 스택과 같은 네트워크를 공유하면서, Vision 컨테이너만 추가로 띄우는 배포 방식입니다.

## 언제 이 모드를 쓰나

- 이미 루트 `docker-compose.yml`로 SCLAB Studio가 설치되어 있다.
- MongoDB / Redis / Qdrant를 Vision과 함께 공유하고 싶다.
- Vision 전용 HTTPS 프록시 대신, 루트 `sclab-proxy`를 그대로 사용하고 싶다.

## 스택 구성

- `vision-aio`: Vision 백엔드, RTSP 수집, HLS gateway, control API, 녹화 처리
- `vision-console`: Vision 웹 콘솔
- 외부 의존 서비스: 루트 스택의 `mongo`, `redis`, `qdrant`, `sclab-proxy`
- 선택 기능: `rustfs` S3 cold tier, GPU 모드

## 설치

```bash
cd vision
./install.sh
```

기본값으로 자동 설치하려면:

```bash
cd vision
./install.sh -y
```

설치 스크립트가 하는 일:

1. Docker와 Docker Compose가 있는지 확인한다.
2. `sclab-network`가 없으면 만든다.
3. 공유 서비스 주소, 녹화 방식, 이미지 태그, 비밀값을 순서대로 묻는다.
4. `vision/.env`를 생성한다.
5. `vision/data/vision/` 아래에 Vision 전용 디렉터리를 만든다.
6. ECR에서 이미지를 받아서 `vision-aio`와 `vision-console`을 시작한다.

루트 스택이 아직 안 떠 있다면 먼저 실행하세요.

```bash
sudo ./run.sh
```

이미 루트 스택을 띄운 상태에서 Vision만 추가하는 경우, Vision HTTPS 포트가 외부에 노출되도록 루트 프록시를 한 번 다시 올리는 것이 좋습니다.

```bash
docker compose up -d sclab-proxy
```

## 접속 주소

루트 `sclab-proxy`가 다음 HTTPS 포트를 외부에 공개합니다.

- 콘솔 웹 UI: `https://<host>:8890`
- 제어 API: `https://<host>:8090`
- HLS gateway: `https://<host>:8080`

루트 스택이 생성한 `cert/cert.pem`과 `cert/privkey.pem`을 사용합니다. 운영용 인증서가 있다면 루트 스택을 시작하기 전에 그 파일로 교체해 두면 됩니다.

## 데이터 위치

- `vision/data/vision/app/`: Vision 앱 데이터
- `vision/data/vision/recordings/`: DVR 녹화의 hot segment
- `vision/data/vision/rustfs/`: S3 cold tier를 사용할 때만 생성되는 RustFS 저장소

## 운영 명령

```bash
cd vision
./up.sh        # 시작
./down.sh      # 중지 및 컨테이너 삭제, 데이터는 유지
./logs.sh      # 로그 보기, 예: ./logs.sh vision-aio
./pull.sh      # 이미지 받기
./restart.sh   # 재시작
./update.sh    # pull + 재생성
```

## 환경 변수 한눈에 보기

`install.sh`가 `vision/.env`를 만들어 줍니다. 아래 표는 "무슨 값을 바꾸는지"와 "쉽게 말하면 무엇인지"를 같이 적었습니다.

### 1) 실행, 이미지, 로그

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_REGISTRY` | `873379329511.dkr.ecr.ap-northeast-2.amazonaws.com/sclabio` | 이미지를 내려받는 저장소 주소 | Vision 컨테이너를 어디서 받아올지 정합니다. |
| `VISION_TAG` | `latest` | 가져올 이미지 태그 | 어떤 버전의 Vision을 쓸지 고릅니다. 보통 `latest`를 씁니다. |
| `VISION_VERSION` | `VISION_TAG`와 동일 | 콘솔과 백엔드가 함께 보는 버전 표기 | 화면에 보이는 "현재 Vision 버전" 표시라고 생각하면 됩니다. |
| `COMPOSE_PROFILES` | `s3` 선택 시 활성화 | `s3` 기능 켜기/끄기 | S3 cold tier 녹화를 쓸 때만 켭니다. |
| `COMPOSE_FILE` | GPU 선택 시 `docker-compose.yml:docker-compose.gpu.yml` | GPU용 오버레이 적용 | NVIDIA GPU를 쓸 때 추가 설정 파일을 붙입니다. |
| `RUST_LOG` | `info` | 로그 자세함 정도 | 보통은 `info`면 충분하고, 문제를 볼 때만 `debug`를 씁니다. |

### 2) 포트와 접속 주소

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_CONSOLE_PORT` | `8890` | 콘솔 HTTPS 포트 | 브라우저로 들어가는 주소의 끝번호입니다. |
| `VISION_CONTROL_PORT` | `8090` | 제어 API HTTPS 포트 | 관리자 API가 열리는 주소입니다. |
| `VISION_GATEWAY_PORT` | `8080` | HLS gateway HTTPS 포트 | 카메라 영상(HLS)을 보는 주소입니다. |

이 세 포트는 컨테이너 내부 포트가 아니라, 루트 프록시가 밖으로 내보내는 포트입니다. 바꿀 때는 프록시 설정도 함께 맞아야 합니다.

### 3) 공유 서비스

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_MONGO_URL` | `mongodb://root:changeThisMongoPassword@mongo:27017/?authSource=admin` | MongoDB 접속 주소 | Vision 설정과 상태를 저장하는 데이터베이스 주소입니다. |
| `VISION_MONGO_DB` | `sclab` | 사용할 MongoDB 데이터베이스 이름 | 같은 MongoDB 안에서 Vision이 어떤 서랍을 쓸지 정합니다. |
| `VISION_REDIS_URL` | `redis://:changeThisRedisPassword@redis:6379` | Redis 접속 주소 | 잠금, 상태, 임시 정보 같은 빠른 데이터를 저장하는 곳입니다. |
| `VISION_STUDIO_SHARED` | `true` | Studio와 DB 이름을 함께 쓰는지 여부 | `true`면 SCLAB Studio와 같은 DB를 공유하므로 이름 충돌을 피하려고 `sv-` 접두사를 붙입니다. |
| `VISION_QDRANT_URL` | `http://qdrant:6333` | Qdrant 접속 주소 | 분석용 벡터 데이터를 저장하는 검색 엔진 주소입니다. |
| `VISION_QDRANT_API_KEY` | `changeThisQdrantApiKey` | Qdrant 비밀키 | Qdrant에 들어갈 때 필요한 비밀번호입니다. |
| `VISION_QDRANT_COLLECTION` | `sv-VisionAnalysisVector` | 벡터 컬렉션 이름 | Qdrant 안에서 Vision 데이터가 들어갈 폴더 이름입니다. |

`VISION_STUDIO_SHARED=true`는 이 문서에서 가장 중요한 값 중 하나입니다. 같은 MongoDB를 쓰더라도, Vision 컬렉션 이름에 `sv-` 접두사를 붙여 SCLAB Studio와 헷갈리지 않게 합니다.

### 4) 로그인과 내부 비밀값

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_INTERNAL_TOKEN` | `sv-dev-internal-token` | Vision 내부 서비스끼리 서로 확인하는 토큰 | 콘솔과 백엔드가 "우리끼리 맞다"를 확인할 때 쓰는 값입니다. |
| `VISION_ADMIN_JWT_SECRET` | `sv-dev-admin-jwt-secret` | 관리자 로그인 토큰 서명값 | 관리자 로그인 쿠키가 위조되지 않았는지 확인합니다. |
| `SESSION_SECRET` | `VISION_ADMIN_JWT_SECRET`와 동일 | 콘솔 세션 쿠키 서명값 | 브라우저 로그인 상태를 지키는 열쇠입니다. |
| `SESSION_MAX_AGE` | `2592000` | 세션 유지 시간(초) | 로그인 상태를 얼마나 오래 기억할지 정합니다. 2592000초는 약 30일입니다. |
| `VISION_SIGNING_KEY` | `dev-insecure-signing-key` | HLS 서명 URL 생성용 키 | HLS 주소에 붙는 서명이 진짜인지 만들 때 쓰는 비밀값입니다. |
| `VISION_SECRET_KEY` | `dev-insecure-secret-key` | Vision 내부 암호화/검증용 비밀값 | 앱 내부에서 민감한 값을 다룰 때 쓰는 추가 비밀값입니다. |

기본값에 들어 있는 `sv-dev-*` 값은 개발용입니다. 운영 환경에서는 반드시 `install.sh`가 생성하는 랜덤 값으로 바꾸세요.

### 5) HLS와 브라우저 접근

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_AIO_CONTROL_ADDR` | `0.0.0.0:8090` | 백엔드가 컨테이너 안에서 듣는 제어 API 주소 | 컨테이너 안에서 관리자 요청을 받는 창구입니다. |
| `VISION_AIO_GATEWAY_ADDR` | `0.0.0.0:8080` | 백엔드가 컨테이너 안에서 듣는 HLS 주소 | 영상 조각을 주고받는 창구입니다. |
| `VISION_AIO_EGRESS_ADDR` | `127.0.0.1:8088` | 내부 egress 전용 주소 | 보통 외부에서 직접 쓰지 않는 내부 통로입니다. |
| `VISION_HLS_CORS_ORIGINS` | `*` | 브라우저에서 HLS를 호출할 수 있는 출처 허용 목록 | 웹페이지가 다른 주소에 있어도 재생할 수 있게 허용합니다. `*`는 모두 허용입니다. |

### 6) 녹화와 S3 cold tier

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_RECORD_DEFAULT` | `off` | 기본 녹화 여부 | 카메라 영상을 기본적으로 저장할지 정합니다. `off`면 저장하지 않습니다. |
| `VISION_RECORD_DIR` | `/var/lib/vision/recordings` | 디스크 녹화 저장 경로 | 컨테이너 안에서 녹화 파일이 쌓이는 위치입니다. |
| `VISION_RECORD_DELETE_AFTER` | `86400` | 녹화 파일 자동 삭제까지 걸리는 시간(초) | 오래된 녹화를 언제 지울지 정합니다. 86400초는 1일입니다. |
| `VISION_S3_BUCKET` | 비어 있음 | S3 cold tier 버킷 이름 | 이 값이 비어 있으면 S3 저장을 쓰지 않고 디스크만 씁니다. |
| `VISION_S3_ENDPOINT` | `http://rustfs:9000` | S3 호환 저장소 주소 | S3처럼 보이는 저장소가 어디 있는지 정합니다. 기본값은 RustFS입니다. |
| `VISION_S3_REGION` | `us-east-1` | S3 리전 이름 | S3 호환 저장소가 위치한 "지역 이름"입니다. 대부분 기본값으로 충분합니다. |
| `VISION_S3_ACCESS_KEY_ID` | `rustfsadmin` | S3 접근 키 ID | S3에 들어갈 때 쓰는 아이디입니다. |
| `VISION_S3_SECRET_ACCESS_KEY` | `rustfsadmin` | S3 비밀 키 | S3에 들어갈 때 쓰는 비밀번호입니다. |
| `VISION_S3_PREFIX` | `recordings` | S3 안에서 파일을 저장할 접두사 | S3 버킷 안의 폴더 이름처럼 생각하면 됩니다. |
| `VISION_S3_ALLOW_HTTP` | `true` | HTTP S3 연결 허용 여부 | 로컬 RustFS 같은 환경에서 암호화 없는 HTTP를 허용합니다. |
| `VISION_S3_FORCE_PATH_STYLE` | `true` | S3 경로 스타일 사용 여부 | 일부 S3 호환 저장소가 필요로 하는 주소 방식입니다. |
| `VISION_S3_API_PORT` | `19000` | RustFS S3 API 외부 포트 | 외부 툴이 RustFS를 S3처럼 접속할 때 쓰는 포트입니다. |
| `VISION_S3_CONSOLE_PORT` | `19001` | RustFS 웹 콘솔 포트 | RustFS 관리자 화면을 여는 포트입니다. |

`VISION_S3_BUCKET`을 채우고 `COMPOSE_PROFILES=s3`를 켜면 `rustfs` 컨테이너가 함께 올라옵니다.

## 초보자용 설정 팁

- Vision을 처음 띄우는 경우에는 `install.sh`의 기본값을 그대로 쓰면 됩니다.
- 공유 스택에서는 MongoDB / Redis / Qdrant 비밀번호를 루트 스택과 똑같이 맞춰야 합니다.
- `VISION_STUDIO_SHARED=true`는 공유 스택에서 거의 항상 그대로 둡니다.
- 녹화를 쓰지 않으면 `VISION_RECORD_DEFAULT=off`로 두면 됩니다.
- 운영 환경에서는 `VISION_INTERNAL_TOKEN`, `VISION_ADMIN_JWT_SECRET`, `VISION_SIGNING_KEY`, `VISION_SECRET_KEY`를 기본값으로 두지 마세요.
