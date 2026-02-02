# Speaches Docker Setup

Docker Compose setup for running [Speaches](https://github.com/speaches-ai/speaches), a speech-to-text service compatible with OpenAI's API.

## Features

- **Automatic GPU Detection**: Automatically switches between GPU (`compose.gpu.yaml`) and CPU (`compose.cpu.yaml`) modes.
- **Model Management**: Interactive shell script to browse and download models.
- **Persistent Storage**: Models are stored in `./data`.
- **Pre-configured Network**: Automatically handles the `sclab-network` Docker network.

## Prerequisites

- **Docker** and **Docker Compose** installed.
- **NVIDIA Drivers** and **NVIDIA Container Toolkit** (if using GPU).
- `curl` (for model downloading script).

## Quick Start

1.  **Run the Service**
    
    The startup script handles network creation and GPU detection automatically.

    ```bash
    ./run.sh
    ```

    - **GPU Mode**: If an NVIDIA GPU is detected, it runs with GPU support.
    - **CPU Mode**: If no GPU is found, it falls back to CPU mode.

2.  **Download Models**

    Use the interactive script to browse and download Whisper models (filtered for "Systran" by default).

    ```bash
    ./download_model.sh
    ```

    Or download a specific model directly:

    ```bash
    ./download_model.sh Systran/faster-whisper-small
    ```

## Usage Details

### Service Endpoints

- **API Base URL**: `http://localhost:8000/v1`
- **Health Check**: `http://localhost:8000/health`
- **Swagger UI**: `http://localhost:8000/docs`

### Directory Structure

- `run.sh`: Main entry point. Detects hardware and starts Docker Compose.
- `download_model.sh`: Script to interactively search and download models from the running service.
- `compose.yaml`: Base Docker Compose configuration.
- `compose.cpu.yaml`: CPU-specific configuration override.
- `compose.gpu.yaml`: GPU-specific resource reservations.
- `data/`: Directory where downloaded models are stored (mounted to container).

## Troubleshooting

- **Permission Issues**: If you encounter permission errors with the `./data` directory, ensure it is writable by the user or pre-create it:
    ```bash
    mkdir -p data
    chmod 777 data
    ```

- **Network Errors**: If `sclab-network` issues persist, `run.sh` attempts to create it automatically. You can also manually create it:
    ```bash
    docker network create sclab-network
    ```
