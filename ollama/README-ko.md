# Ollama 설치

> English version: [README.md](README.md)

## CPU 전용 실행

CPU만 사용하는 경우에는 아래 명령으로 바로 실행할 수 있습니다.

```bash
docker compose up -d
```

## GPU 실행

GPU를 사용하려면 먼저 NVIDIA Container Toolkit을 설치해야 합니다.

### NVIDIA Container Toolkit 설치

#### NVIDIA GPU 설치 - APT 기반

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

#### NVIDIA GPU 설치 - Yum 또는 Dnf 기반

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo yum -y module install nvidia-driver:535-dkms
sudo yum install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### NVIDIA GPU로 실행

```bash
docker compose -f ollama-gpu-nvidia.yml up -d
```

### AMD GPU로 실행

```bash
docker compose -f ollama-gpu-amd.yml up -d
```

## 모델 내려받기

자주 쓰는 임베딩 모델과 LLM 모델을 컨테이너 안에서 직접 내려받을 수 있습니다.

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
