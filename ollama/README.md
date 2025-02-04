# Install ollama

## run CPU only

~~~bash
docker compose up -d
~~~

## run GPU

### Install the NVIDIA Container Toolkit

#### NVIDIA GPU Install with APT

~~~bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
~~~

#### NVIDIA GPU Install with Yum or Dnf

~~~bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo yum install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
~~~

### run NVIDIA

~~~bash
docker compose -f ollama-gpu-nvidia.yml up -d
~~~

### AMD GPU

~~~bash
docker compose -f ollama-gpu-amd.yml up -d
~~~

## pull model

~~~bash
### embedding model
docker exec -it ollama ollama pull mxbai-embed-large
### LLM model
docker exec -it ollama ollama pull gemma2:9b
~~~
