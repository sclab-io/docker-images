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

### 3) Database connection (the only server settings left as environment variables)

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_MONGO_URL` | `mongodb://root:changeThisMongoPassword@mongo:27017/?authSource=admin` | MongoDB connection string | Where Vision stores **all** configuration, secrets and state. |
| `VISION_MONGO_DB` | `sclab_vision` | MongoDB database name | The MongoDB database Vision uses. |
| `VISION_REDIS_URL` | `redis://:changeThisRedisPassword@redis:6379` | Redis connection string | Where Vision stores fast, temporary state. |
| `VISION_STUDIO_SHARED` | `false` | Shared Studio mode flag | When `true`, Vision shares the same MongoDB and prefixes names with `sv-`. |

Nothing else is configured through environment variables any more.

### 4) Everything else lives in MongoDB (Console → Settings → Advanced tuning)

Thresholds, addresses, ports, model file names, recording/S3 policy, AI endpoints, and **secrets** are stored in MongoDB and edited in the console (Settings page, tabs). One save is applied to every node automatically.

- **First-boot defaults**: `install.sh` writes `./data/vision/app/runtime-config.seed.json` (Qdrant address, recording policy, S3, CPU/GPU execution provider, …). `vision-aio` fills **only the keys that are not in the database yet**, so values saved in the console always win. Edit the file *before the first start* if you want different defaults.
- **Secrets are automatic**: the signing key, internal token, admin JWT secret, viewer secret and session secret are generated on first boot and stored **encrypted** in MongoDB (the encryption key is derived from the MongoDB password). They are never shown in the console; you can replace or regenerate them there.
- ⚠ **Changing the MongoDB password** makes the stored secrets undecryptable — re-enter them in the console (auto-generated ones: press *Regenerate*; regenerating the signing key invalidates issued playback links).
- ⚠ **Upgrading from an older install**: the old `.env` values for these settings (secrets, Qdrant, recording, S3, AI keys, …) are **ignored**. Re-enter what you need in the console. If you stored face photos or camera passwords before, keep `VISION_SECRET_KEY` in `.env` for the first start after upgrading so they can still be decrypted (read-only), then remove it.

## Beginner tips

- Leave the defaults as they are if you are starting Vision for the first time.
- MongoDB / Redis / Qdrant credentials in this stack are local to this folder, so keep those passwords safe.
- Recording is `always` on by default. Set `VISION_RECORD_DEFAULT=off` if you do not need DVR recording.
- Change the default MongoDB/Redis passwords before production — the server secrets are encrypted with a key derived from the MongoDB password.
- If you do not have a GPU, leave the mode as CPU. GPU mode requires Linux, NVIDIA drivers, and `nvidia-container-toolkit`.

## Troubleshooting

### `pull access denied ... authorization token has expired`

ECR authorization tokens **expire after 12 hours**. `./pull.sh` and `./update.sh` re-authenticate on every run
(`_ecr.sh`), so simply running them again is usually enough. If it still fails, your AWS credentials are missing
or expired.

```bash
aws configure                 # when no credentials are set (access key / secret / region ap-northeast-2)
./pull.sh && ./up.sh
```

To log in manually:

```bash
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 873379329511.dkr.ecr.ap-northeast-2.amazonaws.com
```

> If you see `aws: command not found`, re-run `./install.sh` — it installs the AWS CLI automatically.
