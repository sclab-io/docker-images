# SCLAB Vision Stand-alone Docker Deployment

> Korean version: [README-ko.md](README-ko.md)

This folder runs Vision as a completely independent stack. It includes MongoDB, Redis, Qdrant, and the HTTPS proxy it needs.

## When to use this mode

- You do not want to install the root SCLAB Studio stack.
- You want Vision to run on a small server or test machine by itself.
- You want Vision to use its own data services instead of sharing the root stack.

## Stack

- `mongo`
- `redis`
- `qdrant`
- `vision-aio`
- `vision-console`
- `vision-tls`: HTTPS proxy for the console, control API, and HLS gateway
- Optional features: `rustfs` S3 cold tier and GPU mode

The container and network names are prefixed with `vision-stand-alone` so they do not conflict with the root SCLAB stack.

## Installation

```bash
cd vision-stand-alone
./install.sh
```

For unattended installation with defaults:

```bash
cd vision-stand-alone
./install.sh -y
```

The installer:

1. Checks whether Docker and Docker Compose are available.
2. Installs AWS CLI if needed and configures AWS credentials when ECR access is required.
3. Prompts for internal service addresses, recording mode, exposed ports, image tag, and secrets.
4. Generates `vision-stand-alone/.env`.
5. Creates the required directories under `vision-stand-alone/data/`.
6. Generates a self-signed TLS certificate in `data/vision/certs/` if one does not exist.
7. Pulls images from ECR and starts the stack.

## Access URLs

- Console web UI: `https://<host>:8890`
- Control API: `https://<host>:8090`
- HLS gateway: `https://<host>:8080`

## Data Layout

- `data/mongo/`: MongoDB data
- `data/redis/`: Redis data
- `data/qdrant/`: Qdrant vector data
- `data/vision/app/`: Vision app data
- `data/vision/recordings/`: DVR hot segment storage
- `data/vision/certs/`: TLS certificate files (`cert.pem`, `privkey.pem`)
- `data/vision/rustfs/`: RustFS storage used only when the `s3` profile is enabled
- `data/vision/rustfs-logs/`: RustFS logs

## Operations

```bash
cd vision-stand-alone
./up.sh        # start
./down.sh      # stop and remove containers; data stays on disk
./logs.sh      # view logs, e.g. ./logs.sh vision-aio
./pull.sh      # pull images
./restart.sh   # restart
./update.sh    # pull and recreate
```

## Environment Variables

`install.sh` generates `vision-stand-alone/.env`. The tables below explain what each variable does in plain language.

### 1) Runtime, images, and logs

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_REGISTRY` | `873379329511.dkr.ecr.ap-northeast-2.amazonaws.com/sclabio` | Image registry | Where Docker pulls the Vision images from. |
| `VISION_TAG` | `latest` | Image tag | Which Vision version to use. |
| `VISION_VERSION` | same as `VISION_TAG` | Displayed version | A version label shown by the console and backend. |
| `COMPOSE_PROFILES` | enabled when `s3` is selected | Compose profile selector | Turns the S3 cold-tier service on or off. |
| `COMPOSE_FILE` | `docker-compose.yml:docker-compose.gpu.yml` when GPU is selected | GPU overlay | Adds the GPU-specific Compose file. |
| `RUST_LOG` | `info` | Log verbosity | `info` is normal; `debug` is for troubleshooting. |

### 2) External ports

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_CONSOLE_PORT` | `8890` | Console HTTPS port | The port used by the browser. |
| `VISION_CONTROL_PORT` | `8090` | Control API HTTPS port | The port used by admin API calls. |
| `VISION_GATEWAY_PORT` | `8080` | HLS gateway HTTPS port | The port used to play camera video. |
| `VISION_S3_API_PORT` | `19000` | RustFS S3 API port | The external port for S3-compatible access. |
| `VISION_S3_CONSOLE_PORT` | `19001` | RustFS console port | The external port for the RustFS management UI. |

### 3) Internal service accounts

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `MONGO_ROOT_USERNAME` | `root` | MongoDB admin username | The MongoDB administrator account name. |
| `MONGO_ROOT_PASSWORD` | random | MongoDB admin password | The top-level password for MongoDB. |
| `REDIS_PASSWORD` | random | Redis password | The password used to access Redis. |
| `VISION_QDRANT_API_KEY` | random | Qdrant API key | The password used to access Qdrant. |

### 4) Vision data storage

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_MONGO_URL` | `mongodb://root:changeThisMongoPassword@mongo:27017/?authSource=admin` | MongoDB connection string | Where Vision stores configuration and state. |
| `VISION_MONGO_DB` | `sclab_vision` | MongoDB database name | The MongoDB database Vision uses. |
| `VISION_REDIS_URL` | `redis://:changeThisRedisPassword@redis:6379` | Redis connection string | Where Vision stores fast, temporary state. |
| `VISION_STUDIO_SHARED` | `false` | Shared Studio mode flag | When `false`, Vision uses its own collection names and data. |
| `VISION_QDRANT_URL` | `http://qdrant:6333` | Qdrant URL | Where Vision stores vector data for analysis. |
| `VISION_QDRANT_COLLECTION` | `VisionAnalysisVector` | Qdrant collection name | The collection that stores Vision vector data. |

`VISION_STUDIO_SHARED=false` is the default here. Stand-alone mode does not share database naming with SCLAB Studio.

### 5) Login and secrets

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_INTERNAL_TOKEN` | `sv-dev-internal-token` | Internal service token | Lets Vision services verify that they belong to the same deployment. |
| `VISION_ADMIN_JWT_SECRET` | `sv-dev-admin-jwt-secret` | Admin JWT signing secret | Prevents admin login tokens from being forged. |
| `SESSION_SECRET` | same as `VISION_ADMIN_JWT_SECRET` | Console session secret | Signs browser session cookies. |
| `SESSION_MAX_AGE` | `2592000` | Session lifetime in seconds | How long the login stays valid. |
| `VISION_SIGNING_KEY` | `dev-insecure-signing-key` | HLS signing key | Used to sign playback URLs. |
| `VISION_SECRET_KEY` | `dev-insecure-secret-key` | Internal secret key | Extra secret used for internal encryption or verification. |

The `sv-dev-*` values are development-only defaults. Replace them with random production secrets.

### 6) HLS and browser access

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_AIO_CONTROL_ADDR` | `0.0.0.0:8090` | Backend control API bind address | Where the backend listens inside the container for admin calls. |
| `VISION_AIO_GATEWAY_ADDR` | `0.0.0.0:8080` | Backend HLS bind address | Where the backend listens for video segment requests. |
| `VISION_AIO_EGRESS_ADDR` | `127.0.0.1:8088` | Internal egress address | An internal path not normally used from outside. |
| `VISION_HLS_CORS_ORIGINS` | `*` | Allowed browser origins | Lets browsers from other origins access HLS. `*` means allow all. |

### 7) Recording and S3 cold tier

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_RECORD_DEFAULT` | `off` | Default recording mode | Whether camera video is saved by default. |
| `VISION_RECORD_DIR` | `/var/lib/vision/recordings` | Local recording directory | Where recording files are stored inside the container. |
| `VISION_RECORD_DELETE_AFTER` | `86400` | Retention time in seconds | How long to keep recordings before deleting them. `86400` seconds is 1 day. |
| `VISION_S3_BUCKET` | empty | S3 bucket name | If this is empty, Vision uses disk-only recording. |
| `VISION_S3_ENDPOINT` | `http://rustfs:9000` | S3-compatible endpoint | Where the S3-compatible storage lives. The default is RustFS. |
| `VISION_S3_REGION` | `us-east-1` | S3 region name | A region label required by many S3 clients. |
| `VISION_S3_ACCESS_KEY_ID` | `rustfsadmin` | S3 access key ID | The username used to access S3 storage. |
| `VISION_S3_SECRET_ACCESS_KEY` | `rustfsadmin` | S3 secret key | The password used to access S3 storage. |
| `VISION_S3_PREFIX` | `recordings` | S3 key prefix | The folder-like path used inside the bucket. |
| `VISION_S3_ALLOW_HTTP` | `true` | Allow HTTP for S3 | Lets Vision use plain HTTP for local RustFS setups. |
| `VISION_S3_FORCE_PATH_STYLE` | `true` | Force path-style S3 URLs | Uses the path-style URL format required by some S3-compatible systems. |
| `VISION_S3_API_PORT` | `19000` | RustFS S3 API port | The external port for S3-compatible access. |
| `VISION_S3_CONSOLE_PORT` | `19001` | RustFS console port | The external port for the RustFS management UI. |

If you set `VISION_S3_BUCKET` and enable the `s3` profile, the `rustfs` container starts automatically.

## Beginner tips

- Leave the defaults as they are if you are starting Vision for the first time.
- MongoDB / Redis / Qdrant credentials in this stack are local to this folder, so keep those passwords safe.
- Leave `VISION_RECORD_DEFAULT=off` if you do not need DVR recording.
- Never keep `VISION_INTERNAL_TOKEN`, `VISION_ADMIN_JWT_SECRET`, `VISION_SIGNING_KEY`, or `VISION_SECRET_KEY` at their development defaults in production.
- If you do not have a GPU, leave the mode as CPU. GPU mode requires Linux, NVIDIA drivers, and `nvidia-container-toolkit`.
