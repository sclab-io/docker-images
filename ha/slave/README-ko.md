# SCLAB HA SLAVE

> English version: [README.md](README.md)

## 설치

### 사전 준비

#### 라이선스 코드

이 이미지는 LICENSE KEY 없이는 사용할 수 없습니다. 라이선스를 받으려면 support@sclab.io로 문의하세요.

#### OS

- ubuntu
- docker
- docker-compose

#### 최소 시스템 요구 사항

- 메모리 8GB
- 여유 공간 40GB

## 1단계. Docker 설치

- Docker 설치 문서: https://docs.docker.com/engine/install/

## 2단계. 파일 내려받기

```bash
git clone https://github.com/sclab-io/docker-images.git
```

## 3단계. 현재 소스의 설정 파일 수정

### setup.sh 편집

- 서버 IP 주소와 도메인을 수정합니다.

```bash
# ip, domain, password 수정
vi ../setup.sh

# 사이트 도메인 수정
# 라이선스 코드 추가
vi settings.json
```

## 4단계. NFS 설정

```bash
./setup-nfs-client.sh
```

비밀번호는 비워 두고 Enter를 누릅니다.

## 5단계. AWS CLI 설치

- 설치 문서: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

### Linux 설치

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

## 6단계. AWS 설정

- SCLAB에서 받은 AWS Access Key ID와 AWS Secret Access Key를 입력합니다.

```bash
sudo aws configure
```

## 7단계. 인스턴스 실행

### 네트워크 생성

```bash
sudo docker network create sclab-network
```

### 데몬 모드로 실행

```bash
sudo ./run.sh
```

이제 호스트 시스템에서 `http://yourdomain.com/`으로 SCLAB Studio에 접속할 수 있습니다.

웹 페이지에 접속한 뒤에는 관리자 계정으로 로그인해야 합니다.

기본 계정 정보는 `settings.json`의 `private.adminEmail`, `private.adminPassword`에 있는 `[admin@sclab.io / admin]`입니다.

웹 페이지에서 관리자 비밀번호를 변경할 수 있으며, `settings.json`의 `private.adminPassword`를 굳이 바꿀 필요는 없습니다.

## 실행 중인 인스턴스 중지

```bash
sudo ./down.sh
```

## 로그 보기

```bash
sudo ./logs.sh
```

## 새 이미지 내려받기

```bash
sudo ./pull.sh
```

## 모든 이미지 업데이트

```bash
sudo ./update-all.sh
```

## 이미지 업데이트 후 webapp 재시작

webapp 이외의 다른 서비스가 업데이트된 경우에는 `./update-all.sh`를 사용하세요.

```bash
sudo ./update.sh
```

## 라이선스

Copyright (c) 2024 SCLAB All rights reserved.
