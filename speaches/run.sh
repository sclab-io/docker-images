#!/bin/bash

check_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

if ! docker network ls | grep -q "sclab-network"; then
    echo "🌐 Network 'sclab-network' not found. Creating it..."
    docker network create sclab-network
fi

if check_gpu; then
    echo "✅ NVIDIA GPU detected. Starting in GPU mode..."
    docker compose -f compose.yaml -f compose.gpu.yaml up -d
else
    echo "⚠️  No NVIDIA GPU detected. Starting in CPU mode using compose.cpu.yaml..."
    docker compose -f compose.cpu.yaml up -d
fi
