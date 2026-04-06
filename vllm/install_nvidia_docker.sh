#!/bin/bash
# This script must be run with root privileges (sudo).

echo "1/4: Configuring NVIDIA Container Toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && \
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo -e "\n2/4: Updating package list and installing..."
apt-get update
apt-get install -y nvidia-container-toolkit

echo -e "\n3/4: Configuring Docker runtime..."
nvidia-ctk runtime configure --runtime=docker

echo -e "\n4/4: Restarting Docker service..."
systemctl restart docker

echo -e "\nCompleted! Now try running 'docker compose up -d' again."
