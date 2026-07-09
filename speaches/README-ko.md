# Speaches Docker 설정

> English version: [README.md](README.md)

OpenAI 호환 API를 제공하는 [Speaches](https://github.com/speaches-ai/speaches)용 Docker Compose 설정입니다. 음성 인식 모델을 내려받고, CPU 또는 GPU 환경에서 실행하는 구성을 함께 제공합니다.

## 기능

- GPU가 있으면 GPU 설정 파일을, 없으면 CPU 설정 파일을 자동으로 사용합니다.
- 모델을 찾아서 내려받는 대화형 스크립트를 제공합니다.
- 다운로드한 모델은 `./data`에 저장합니다.
- `sclab-network`를 자동으로 사용합니다.

## 준비물

- Docker
- Docker Compose
- GPU를 쓸 경우 NVIDIA 드라이버와 NVIDIA Container Toolkit
- 모델 다운로드용 `curl`

## 빠른 시작

1. 서비스 시작

```bash
./run.sh
```

2. 모델 다운로드

```bash
./download_model.sh
```

이 스크립트는 기본적으로 Systran 계열 Whisper 모델을 찾기 쉽도록 도와줍니다.

특정 모델을 바로 받으려면:

```bash
./download_model.sh Systran/faster-whisper-small
```

## 접속 주소

- API Base URL: `http://localhost:8000/v1`
- Health Check: `http://localhost:8000/health`
- Swagger UI: `http://localhost:8000/docs`

## 디렉터리

- `run.sh`: GPU 감지와 Docker Compose 실행
- `download_model.sh`: 모델 검색 및 다운로드
- `compose.yaml`: 기본 Compose 설정
- `compose.cpu.yaml`: CPU 설정
- `compose.gpu.yaml`: GPU 설정
- `data/`: 다운로드한 모델 저장소

## 참고

- GPU가 없으면 CPU 설정으로 자동 전환됩니다.
- `data` 아래에 저장된 모델은 다시 내려받지 않아도 재사용됩니다.
- `sclab-network`는 다른 SCLAB 예시와 네트워크를 공유할 때 사용합니다.

## 문제 해결

- `./data` 권한 문제가 있으면 다음을 실행하세요.

```bash
mkdir -p data
chmod 777 data
```

- `sclab-network`가 없으면 `run.sh`가 만들려고 시도합니다. 필요하면 직접 만들 수 있습니다.

```bash
docker network create sclab-network
```
