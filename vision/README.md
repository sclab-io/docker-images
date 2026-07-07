# SCLAB Vision — Docker 배포

RTSP→HLS 스트리밍 서버 SCLAB Vision을 `docker compose`로 설치·운영합니다. 기본 구성은 **`vision-aio`(올인원) + `vision-console`(웹 UI)** 입니다.

## 빠른 설치

```sh
./install.sh
```

단계별로 물어보며, **전부 Enter만 치면 기본값**으로 설치됩니다. 질문 없이 기본값으로 바로 설치하려면 `./install.sh -y`.

설치가 하는 일:
1. 배포판 감지 + Docker/Compose 확인(없으면 설치 제안 — Ubuntu/Debian/Fedora/RHEL·Rocky·Alma/openSUSE/Arch/Alpine)
2. 공유 네트워크 `sclab-network` 생성(없을 때)
3. 6단계 질문 → `.env` 생성
4. `./data/vision/*` 볼륨 디렉터리 생성
5. (ECR이면) 자동 로그인 → 이미지 pull → `up -d`

## 설치 질문(요약)

| 단계 | 내용 | 기본값 |
|---|---|---|
| 1 가속기 | GPU(NVIDIA) 사용 | CPU |
| 2 DB | ① Vision 전용 Mongo/Redis  ② SCLAB Studio 공유 | ① 전용 |
| 3 녹화 | ① 안 함  ② 디스크  ③ 디스크+S3(RustFS) | ① 안 함 |
| 4 포트 | 콘솔 8890 · gateway 8080 · control 8090 | 좌측 |
| 5 이미지 | 레지스트리(ECR) · 태그 | latest |
| 6 시크릿 | 자동 랜덤 생성 | 자동 생성 |

## 운영 명령

```sh
./up.sh        # 기동(docker compose up -d)
./down.sh      # 중지(컨테이너 제거 — ./data/vision 데이터는 유지)
./logs.sh      # 로그 팔로우 (예: ./logs.sh vision-aio)
./restart.sh   # 재시작
./pull.sh      # 최신 이미지 pull
./update.sh    # pull + 롤링 재기동
```

## 구조

- **네트워크**: `sclab-network`(external) — 형제 SCLAB 스택과 공유. `install.sh`가 없으면 생성합니다.
- **볼륨**: 전부 `./data/vision/` 아래 바인드마운트
  - `recordings/` DVR hot 세그먼트 · `mongo/` `redis/` 전용 DB · `rustfs/` S3(cold) 저장
- **설정**: `.env`(install.sh 생성, 직접 편집 가능 — 변경 후 `./up.sh`). 전체 항목은 [`.env.example`](.env.example) 참고.
- **compose profiles**: `db`(전용 Mongo/Redis) · `s3`(RustFS). `.env`의 `COMPOSE_PROFILES`로 제어.
- **GPU**: 선택 시 `.env`에 `COMPOSE_FILE=docker-compose.yml:docker-compose.gpu.yml`이 기록되어 aio가 `vision-aio-gpu`로 교체되고 GPU가 예약됩니다(호스트에 `nvidia-container-toolkit` 필요).

## 접속

- 콘솔 웹 UI: `http://<host>:8890`
- 제어 API: `http://<host>:8090`
- HLS gateway(외부 재생 표면): `http://<host>:8080`

## SCLAB Studio 공유 모드

설치 2단계에서 "공유"를 선택하면 Studio의 `mongo`/`redis`(같은 `sclab-network`)를 그대로 쓰고, `VISION_STUDIO_SHARED=true`로 컬렉션에 `sv-` prefix를 붙여 충돌을 피합니다. 이때 Studio 스택이 먼저 실행 중이어야 합니다.

> ⚠ 기본 시크릿(`sv-dev-*`)은 개발용입니다. 운영에서는 설치 시 자동 생성(6단계 기본)을 쓰거나 `.env`의 `VISION_INTERNAL_TOKEN`/`VISION_ADMIN_JWT_SECRET`/`VISION_SIGNING_KEY`를 직접 교체하세요.
