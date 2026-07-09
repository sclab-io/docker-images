# Ollama 설치

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
