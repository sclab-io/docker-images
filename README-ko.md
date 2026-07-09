# SCLAB Docker Images

> English version: [README.md](README.md)

이 저장소는 SCLAB Studio와 관련 서비스의 Docker 이미지와 배포 예시를 모아 둔 곳입니다.

## 빠른 안내

- Vision 문서:
  - [vision/README.md](vision/README.md)
  - [vision/README-ko.md](vision/README-ko.md)
  - [vision-stand-alone/README.md](vision-stand-alone/README.md)
  - [vision-stand-alone/README-ko.md](vision-stand-alone/README-ko.md)
- 다른 예시:
  - `ollama/`
  - `speaches/`
  - `kafka-docker/`
  - `kafka-docker-elastic/`
  - `k8s/`
  - `ha/`
  - `mongo-replica-set/`

## SCLAB이란

SCLAB은 여러 데이터를 한곳에 모아 시각화와 운영을 쉽게 만드는 플랫폼입니다. 이 저장소는 그 플랫폼을 Docker 환경에서 실행하는 데 필요한 이미지와 예시 구성을 제공합니다.

## Vision 배포 방식

- `vision/`: 루트 SCLAB Studio 스택과 MongoDB / Redis / Qdrant를 공유하는 방식
- `vision-stand-alone/`: Vision만 독립적으로 실행하는 방식

두 방식 모두 GPU 모드와 DVR 녹화를 지원합니다. 포트, 데이터 위치, 환경변수의 역할은 각 폴더의 README에 자세히 적혀 있습니다.

## 설치 개요

루트 스택을 먼저 설치하는 경우:

```bash
sudo ./run.sh
```

Vision만 추가하는 경우:

```bash
cd vision
./install.sh
```

Vision만 단독으로 쓰는 경우:

```bash
cd vision-stand-alone
./install.sh
```

## 주의할 점

- `README.md`는 영어 기준 문서입니다.
- `README-ko.md`는 한국어 안내용입니다.
- Vision의 세부 설정은 각 폴더의 README를 먼저 보는 것이 가장 정확합니다.
- 운영 환경에서는 기본 비밀번호와 기본 시크릿 값을 그대로 쓰지 않는 것이 좋습니다.

## 다른 예시

- `ollama/`: Ollama 실행 예시
- `speaches/`: OpenAI 호환 음성 인식 서비스 예시
- `kafka-docker/`, `kafka-docker-elastic/`: Kafka / ksqlDB / Connector 예시
- `k8s/`: Kubernetes 배포 예시
- `ha/`: 고가용성 구성 예시
- `mongo-replica-set/`: MongoDB Replica Set 예시

루트 `README.md`는 영어 버전이 기준이며, 이 파일은 한국어 빠른 안내용입니다.
