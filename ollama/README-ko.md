# Ollama 설치

> English version: [README.md](README.md)

이 예시는 Ollama를 Docker로 실행하는 방법을 정리한 문서입니다. CPU만 있는 서버에서도 실행할 수 있고, NVIDIA GPU나 AMD GPU가 있으면 가속도 사용할 수 있습니다.

## 실행 방식 선택

- CPU만 쓸 때는 기본 `docker compose up -d`로 시작합니다.
- NVIDIA GPU를 쓸 때는 `ollama-gpu-nvidia.yml`을 사용합니다.
- AMD GPU를 쓸 때는 `ollama-gpu-amd.yml`을 사용합니다.

## CPU로 실행

```bash
docker compose up -d
```

## GPU로 실행

### NVIDIA Container Toolkit 설치

#### APT 기반 배포판

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install nvidia-driver-535
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

#### Yum/Dnf 기반 배포판

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo yum -y module install nvidia-driver:535-dkms
sudo yum install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### NVIDIA로 실행

```bash
docker compose -f ollama-gpu-nvidia.yml up -d
```

### AMD GPU로 실행

```bash
docker compose -f ollama-gpu-amd.yml up -d
```

## 모델 받기

자주 쓰는 모델은 컨테이너 안에서 직접 내려받습니다. 아래 예시는 임베딩 모델과 대형 언어 모델, 그리고 동작 확인용 명령입니다.

```bash
# embedding model
docker exec -it ollama ollama pull mxbai-embed-large
# LLM model
docker exec -it ollama ollama pull gpt-oss:20b
# test
docker exec -it ollama ollama run gpt-oss:20b
# process check
docker exec -it ollama ollama ps
```
