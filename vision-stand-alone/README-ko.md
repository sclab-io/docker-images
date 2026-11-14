# SCLAB Vision Stand-alone Docker Deployment

> English version: [README.md](README.md)

이 폴더는 Vision만 독립적으로 실행하는 배포 방식입니다. MongoDB / Redis / Qdrant / HTTPS 프록시까지 이 폴더 안의 Compose가 모두 올립니다.

## 언제 이 모드를 쓰나

- SCLAB Studio 루트 스택을 설치하지 않고 Vision만 쓰고 싶다.
- 테스트 서버나 소규모 서버에서 Vision을 독립적으로 운영하고 싶다.
- 공유 DB를 건드리지 않고 Vision 전용 저장소를 쓰고 싶다.

## 스택 구성

- `mongo`
- `redis`
- `qdrant`
- `vision-aio`
- `vision-console`
- `vision-tls`: 콘솔, 제어 API, HLS gateway용 HTTPS 프록시
- 선택 기능: `rustfs` S3 cold tier, GPU 모드

`vision-stand-alone`라는 이름이 붙은 네트워크와 컨테이너 이름을 써서, 루트 SCLAB 스택과 충돌하지 않게 만듭니다.

## 설치

```bash
cd vision-stand-alone
./install.sh
```

기본값으로 자동 설치하려면:

```bash
cd vision-stand-alone
./install.sh -y
```

설치 스크립트가 하는 일:

1. Docker와 Docker Compose가 있는지 확인한다.
2. AWS CLI가 없으면 설치하고, ECR 접근이 필요하면 AWS 자격 증명도 설정한다.
3. 내부 서비스 주소, 녹화 방식, 외부 포트, 이미지 태그, 비밀값을 순서대로 묻는다.
4. `vision-stand-alone/.env`를 만든다.
5. `vision-stand-alone/data/` 아래에 필요한 디렉터리를 만든다.
6. `data/vision/certs/`에 인증서가 없으면 자체 서명 TLS 인증서를 생성한다.
7. ECR에서 이미지를 받아서 스택을 시작한다.

## 접속 주소

- 콘솔 웹 UI: `https://<host>:8890`
- 제어 API: `https://<host>:8090`
- HLS gateway: `https://<host>:8080`

## 데이터 위치

- `data/mongo/`: MongoDB 데이터
- `data/redis/`: Redis 데이터
- `data/qdrant/`: Qdrant 벡터 데이터
- `data/vision/app/`: Vision 앱 데이터
- `data/vision/recordings/`: DVR 녹화의 hot segment
- `data/vision/certs/`: TLS 인증서 파일(`cert.pem`, `privkey.pem`)
- `data/vision/rustfs/`: S3 cold tier를 사용할 때만 생성되는 RustFS 저장소
- `data/vision/rustfs-logs/`: RustFS 로그

## 운영 명령

```bash
cd vision-stand-alone
./up.sh        # 시작
./down.sh      # 중지 및 컨테이너 삭제, 데이터는 유지
./logs.sh      # 로그 보기, 예: ./logs.sh vision-aio
./pull.sh      # 이미지 받기
./restart.sh   # 재시작
./update.sh    # pull + 재생성
```

## 환경 변수 한눈에 보기

`install.sh`가 `vision-stand-alone/.env`를 만들어 줍니다. 아래 표는 초보자도 읽을 수 있게 "무슨 값을 바꾸는지"를 풀어서 적었습니다.

### 1) 실행, 이미지, 로그

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_REGISTRY` | `873379329511.dkr.ecr.ap-northeast-2.amazonaws.com/sclabio` | 이미지를 내려받는 저장소 주소 | Vision 컨테이너를 어디서 받아올지 정합니다. |
| `VISION_TAG` | `latest` | 가져올 이미지 태그 | 어떤 버전의 Vision을 쓸지 고릅니다. |
| `VISION_VERSION` | `VISION_TAG`와 동일 | 콘솔과 백엔드가 함께 보는 버전 표기 | 화면에 보이는 현재 버전 값입니다. |
| `COMPOSE_PROFILES` | `s3` 선택 시 활성화 | `s3` 기능 켜기/끄기 | S3 cold tier를 쓸 때만 켭니다. |
| `COMPOSE_FILE` | GPU 선택 시 `docker-compose.yml:docker-compose.gpu.yml` | GPU용 오버레이 적용 | NVIDIA GPU를 쓸 때 추가 설정 파일을 붙입니다. |
| `RUST_LOG` | `info` | 로그 자세함 정도 | 기본은 `info`, 문제가 있을 때만 `debug`를 씁니다. |

### 2) 외부 포트

| 변수 | 기본값 | 역할 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_CONSOLE_PORT` | `8890` | 콘솔 HTTPS 포트 | 브라우저로 여는 주소의 끝번호입니다. |
| `VISION_CONTROL_PORT` | `8090` | 제어 API HTTPS 포트 | 관리자용 API가 열리는 포트입니다. |
| `VISION_GATEWAY_PORT` | `8080` | HLS gateway HTTPS 포트 | 카메라 영상이 재생되는 포트입니다. |
| `VISION_S3_API_PORT` | `19000` | RustFS S3 API 외부 포트 | S3 호환 저장소를 외부 도구에서 볼 때 쓰는 포트입니다. |
| `VISION_S3_CONSOLE_PORT` | `19001` | RustFS 웹 콘솔 포트 | RustFS 관리 화면을 여는 포트입니다. |

### 3) DB 접속 (환경 변수로 남은 유일한 서버 설정)

| 변수 | 기본값 | 용도 | 쉽게 말하면 |
|---|---|---|---|
| `VISION_MONGO_URL` | `mongodb://root:changeThisMongoPassword@mongo:27017/?authSource=admin` | MongoDB 접속 문자열 | Vision이 **모든** 설정·시크릿·상태를 저장하는 곳입니다. |
| `VISION_MONGO_DB` | `sclab_vision` | MongoDB 데이터베이스 이름 | Vision이 사용할 MongoDB 데이터베이스입니다. |
| `VISION_REDIS_URL` | `redis://:changeThisRedisPassword@redis:6379` | Redis 접속 문자열 | 빠르게 바뀌는 임시 상태를 저장하는 곳입니다. |
| `VISION_STUDIO_SHARED` | `false` | 공유 Studio 모드 | `true`이면 같은 MongoDB를 공유하고 이름 앞에 `sv-`를 붙여 충돌을 피합니다. |

그 외의 설정은 더 이상 환경 변수로 지정하지 않습니다.

### 4) 나머지는 모두 MongoDB (콘솔 → 설정 → 고급 튜닝)

임계값, 주소, 포트, 모델 파일명, 녹화·S3 정책, AI 엔드포인트, **시크릿**은 MongoDB에 저장되고 콘솔 설정 화면(탭)에서 편집합니다. 한 번 저장하면 모든 노드에 자동 반영됩니다.

- **첫 부팅 기본값**: `install.sh`가 `./data/vision/app/runtime-config.seed.json`(Qdrant 주소, 녹화 정책, S3, CPU/GPU 실행기 등)을 만듭니다. `vision-aio`는 **DB에 아직 없는 키만** 채우므로 콘솔에서 저장한 값이 항상 우선합니다. 기본값을 바꾸려면 *처음 시작하기 전에* 이 파일을 수정하세요.
- **시크릿은 자동**: 서명키·내부 토큰·관리자 JWT 시크릿·뷰어 비밀·세션 시크릿은 첫 부팅에 생성되어 MongoDB에 **암호화**되어 저장됩니다(암호화 키는 MongoDB 비밀번호에서 파생). 콘솔에는 값이 표시되지 않으며 교체·재생성할 수 있습니다.
- ⚠ **MongoDB 비밀번호를 바꾸면** 저장된 시크릿을 복호할 수 없습니다 — 콘솔에서 다시 입력하세요(자동 생성 항목은 *재생성*, 서명키를 재생성하면 이미 발급된 재생 링크가 무효가 됩니다).
- ⚠ **기존 설치에서 업그레이드할 때**: 예전 `.env`의 이 항목들(시크릿, Qdrant, 녹화, S3, AI 키 등)은 **무시**됩니다. 필요한 값은 콘솔에서 다시 입력하세요. 이전에 얼굴 사진이나 카메라 비밀번호를 저장했다면, 업그레이드 후 첫 시작에는 `.env`에 `VISION_SECRET_KEY`를 남겨 두어야 읽을 수 있습니다(복호 전용). 이후 제거해도 됩니다.

## 초보자용 설정 팁

- Vision을 처음 띄우는 경우에는 `install.sh`의 기본값을 그대로 써도 됩니다.
- 공유 스택에서는 MongoDB / Redis / Qdrant 비밀번호를 루트 스택과 똑같이 맞춰야 합니다.
- `VISION_STUDIO_SHARED=true`는 공유 스택에서 거의 항상 그대로 둡니다.
- 기본값은 상시 녹화(`always`)입니다. 녹화를 쓰지 않으면 `VISION_RECORD_DEFAULT=off`로 바꾸면 됩니다.
- 운영 환경에서는 MongoDB/Redis 기본 비밀번호를 바꾸세요. 서버 시크릿은 MongoDB 비밀번호에서 파생한 키로 암호화됩니다.

## 문제 해결

### `pull access denied ... authorization token has expired`

ECR 인증 토큰은 **12시간이면 만료**됩니다. `./pull.sh`와 `./update.sh`는 실행할 때마다 자동으로 재로그인하므로
(`_ecr.sh`), 보통은 그대로 다시 실행하면 됩니다. 그래도 실패한다면 AWS 자격증명이 없거나 만료된 것입니다.

```bash
aws configure                 # 자격증명이 없을 때(액세스 키/시크릿/리전 ap-northeast-2)
./pull.sh && ./up.sh
```

수동으로 로그인하려면:

```bash
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 873379329511.dkr.ecr.ap-northeast-2.amazonaws.com
```

> `aws: command not found`이면 `./install.sh`를 다시 실행하세요(AWS CLI를 자동 설치합니다).
