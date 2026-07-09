# SCLAB Docker Images

이 저장소는 SCLAB Studio와 관련 서비스의 Docker 이미지와 배포 예시를 모아 둔 곳입니다.

## Vision 문서

- [vision/README.md](vision/README.md): 루트 SCLAB Studio 스택과 Vision을 공유하는 배포 방식
- [vision-stand-alone/README.md](vision-stand-alone/README.md): Vision만 독립적으로 실행하는 배포 방식

Vision은 두 모드 모두 GPU 모드와 DVR 녹화를 지원합니다. 포트, 데이터 위치, 환경변수의 의미는 각 폴더의 README에 자세히 정리되어 있습니다.

## 다른 예시

- `ollama/`: Ollama 실행 예시
- `speaches/`: Speaches 음성 인식 예시
- `kafka-docker/`, `kafka-docker-elastic/`: Kafka 관련 예시
- `k8s/`: Kubernetes 배포 예시
- `ha/`: HA 구성 예시
- `mongo-replica-set/`: MongoDB Replica Set 구성 예시

루트 `README.md`는 영어 버전이 기준이며, 이 파일은 한국어 안내용입니다.
