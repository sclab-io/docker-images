# Speaches Docker 설정

> English version: [README.md](README.md)

OpenAI API와 호환되는 음성-텍스트 서비스 [Speaches](https://github.com/speaches-ai/speaches)를 실행하기 위한 Docker Compose 설정입니다.

## 기능

- GPU가 있으면 GPU용 구성(`compose.gpu.yaml`)을 사용하고, 없으면 CPU용 구성(`compose.cpu.yaml`)으로 자동 전환합니다.
- 모델을 찾아서 내려받는 대화형 스크립트를 제공합니다.
- 내려받은 모델은 `./data` 디렉터리에 저장됩니다.
- `sclab-network` Docker 네트워크를 자동으로 사용합니다.

## 사전 준비

- Docker와 Docker Compose가 설치되어 있어야 합니다.
- GPU를 사용할 경우 NVIDIA 드라이버와 NVIDIA Container Toolkit이 필요합니다.
- 모델 다운로드 스크립트 실행을 위해 `curl`이 필요합니다.

## 빠른 시작

1. 서비스 실행

   시작 스크립트가 네트워크 생성과 GPU 감지를 자동으로 처리합니다.

   ```bash
   ./run.sh
   ```

   - GPU 모드: NVIDIA GPU가 감지되면 GPU 지원 모드로 실행합니다.
   - CPU 모드: GPU를 찾지 못하면 CPU 모드로 실행합니다.

2. 모델 다운로드

   대화형 스크립트로 Whisper 모델을 찾아 내려받을 수 있습니다. 기본적으로 "Systran" 계열 모델만 보여 줍니다.

   ```bash
   ./download_model.sh
   ```

   특정 모델을 바로 내려받을 수도 있습니다.

   ```bash
   ./download_model.sh Systran/faster-whisper-small
   ```

## 사용 상세

### 서비스 엔드포인트

- API Base URL: `http://localhost:8000/v1`
- Health Check: `http://localhost:8000/health`
- Swagger UI: `http://localhost:8000/docs`

### 디렉터리 구조

- `run.sh`: 기본 진입점. 하드웨어를 감지하고 Docker Compose를 시작합니다.
- `download_model.sh`: 실행 중인 서비스에서 모델을 대화형으로 검색하고 다운로드합니다.
- `compose.yaml`: 기본 Docker Compose 설정입니다.
- `compose.cpu.yaml`: CPU 전용 설정 오버레이입니다.
- `compose.gpu.yaml`: GPU 전용 리소스 예약 설정입니다.
- `data/`: 내려받은 모델이 저장되는 디렉터리입니다. 컨테이너에 마운트됩니다.

## 문제 해결

- 권한 문제: `./data` 디렉터리에 권한 오류가 나면, 쓰기 가능하도록 만들거나 미리 생성하세요.

  ```bash
  mkdir -p data
  chmod 777 data
  ```

- 네트워크 문제: `sclab-network`에 문제가 있으면 `run.sh`가 자동으로 생성하려고 시도합니다. 필요하면 직접 생성할 수도 있습니다.

  ```bash
  docker network create sclab-network
  ```
