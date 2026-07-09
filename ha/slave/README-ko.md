# SCLAB HA SLAVE

> English version: [README.md](README.md)

이 문서는 HA 구성에서 Slave 서버에 들어가는 설정을 정리합니다.

## 설치 준비

### 라이선스

이 이미지는 LICENSE KEY 없이는 사용할 수 없습니다. 라이선스를 받으려면 [support@sclab.io](mailto://support@sclab.io)로 문의하세요.

### OS

- ubuntu
- docker
- docker-compose

### 최소 사양

- 메모리 8GB
- 여유 공간 40GB

## 1. Docker 설치

[Docker 설치 문서](https://docs.docker.com/engine/install/)

## 2. 파일 다운로드

```bash
git clone https://github.com/sclab-io/docker-images.git
```

## 3. 설정 수정

- `../setup.sh`에서 서버 IP와 도메인을 수정합니다.
- `settings.json`에 사이트 도메인과 라이선스를 넣습니다.

## 4. NFS 클라이언트 설정

```bash
./setup-nfs-client.sh
```

## 5. AWS CLI 설치 및 설정

AWS CLI를 설치하고 `aws configure`를 실행합니다.

## 6. 실행

```bash
sudo docker network create sclab-network
sudo ./run.sh
```

이후 브라우저에서 SCLAB Studio에 접속하면 됩니다.

## 참고

- Slave 쪽에는 웹앱 인스턴스가 여러 개 올라갑니다.
- NFS 클라이언트 설정이 Master와 맞아야 합니다.
- AWS CLI와 네트워크 설정이 완료되어야 정상적으로 동작합니다.
