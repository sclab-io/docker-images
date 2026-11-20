# SCLAB Vision Docker Deployment

> Korean version: [README-ko.md](README-ko.md)

This folder runs SCLAB Vision alongside the root SCLAB Studio stack. Vision shares MongoDB, Redis, Qdrant, and the root HTTPS proxy.

## When to use this mode

- SCLAB Studio is already installed from the repository root.
- You want Vision to share MongoDB, Redis, and Qdrant with the main stack.
- You want to reuse the root `sclab-proxy` instead of running a separate proxy.

## Stack

- `vision-aio`: Vision backend, RTSP ingest, HLS gateway, control API, and recording
- `vision-console`: Vision web console
- Shared services from the root stack: `mongo`, `redis`, `qdrant`, `sclab-proxy`
- Optional features: `rustfs` S3 cold tier and GPU mode

## Installation

```bash
cd vision
./install.sh
```

For unattended installation with defaults:

```bash
cd vision
./install.sh -y
```

The installer:

1. Checks whether Docker and Docker Compose are available.
2. Creates `sclab-network` if it does not exist.
3. Prompts for shared service endpoints, recording mode, image tag, and secrets.
4. Generates `vision/.env`.
5. Creates Vision-owned directories under `vision/data/vision/`.
6. Pulls images from ECR and starts `vision-aio` and `vision-console`.

If the root stack is not running yet, start it first:

```bash
sudo ./run.sh
```

If the root stack is already running, re-create the root proxy so the Vision ports are published:

```bash
docker compose up -d sclab-proxy
```

## Access URLs

The root `sclab-proxy` publishes these HTTPS endpoints:

- Console web UI: `https://<host>:8890`
- Control API: `https://<host>:8090`
- HLS gateway: `https://<host>:8080`

The root stack uses `cert/cert.pem` and `cert/privkey.pem`. If you have a production certificate, replace those files before starting the root stack.

## Data Layout

- `vision/data/vision/app/`: Vision app data
- `vision/data/vision/recordings/`: DVR hot segment storage
- `vision/data/vision/rustfs/`: RustFS storage used only when the `s3` profile is enabled

## Operations

```bash
cd vision
./up.sh        # start
./down.sh      # stop and remove containers; data stays on disk
./logs.sh      # view logs, e.g. ./logs.sh vision-aio
./pull.sh      # pull images
./restart.sh   # restart
./update.sh    # pull and recreate
```

## Environment Variables

`install.sh` generates `vision/.env`. The tables below explain what each variable does in plain language.

### 1) Runtime, images, and logs

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_REGISTRY` | `873379329511.dkr.ecr.ap-northeast-2.amazonaws.com/sclabio` | Image registry | Where Docker pulls the Vision images from. |
| `VISION_TAG` | `latest` | Image tag | Which Vision version to use. |
| `VISION_VERSION` | same as `VISION_TAG` | Displayed version | A version label shown by the console and backend. |
| `COMPOSE_PROFILES` | enabled when `s3` is selected | Compose profile selector | Turns the S3 cold-tier service on or off. |
| `COMPOSE_FILE` | `docker-compose.yml:docker-compose.gpu.yml` when GPU is selected | GPU overlay | Adds the GPU-specific Compose file. |
| `RUST_LOG` | `info` | Log verbosity | `info` is normal; `debug` is for troubleshooting. |

### 2) Ports

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_CONSOLE_PORT` | `8890` | Console HTTPS port | The port used by the browser. |
| `VISION_CONTROL_PORT` | `8090` | Control API HTTPS port | The port used by admin API calls. |
| `VISION_GATEWAY_PORT` | `8080` | HLS gateway HTTPS port | The port used to play camera video. |

These are external ports exposed by the root proxy. If you change them, the proxy configuration must match.

### 3) Database connection (the only server settings left as environment variables)

| Variable | Default | Purpose | Plain explanation |
|---|---|---|---|
| `VISION_MONGO_URL` | `mongodb://root:changeThisMongoPassword@mongo:27017/?authSource=admin` | MongoDB connection string | Where Vision stores **all** configuration, secrets and state. |
| `VISION_MONGO_DB` | `sclab` | MongoDB database name | The MongoDB database Vision uses. |
| `VISION_REDIS_URL` | `redis://:changeThisRedisPassword@redis:6379` | Redis connection string | Where Vision stores fast, temporary state. |
| `VISION_STUDIO_SHARED` | `true` | Shared Studio mode flag | When `true`, Vision shares the same MongoDB and prefixes names with `sv-`. |

Nothing else is configured through environment variables any more.

### 4) Everything else lives in MongoDB (Console → Settings → Advanced tuning)

Thresholds, addresses, ports, model file names, recording/S3 policy, AI endpoints, and **secrets** are stored in MongoDB and edited in the console (Settings page, tabs). One save is applied to every node automatically.

- **First-boot defaults**: `install.sh` writes `./data/vision/app/runtime-config.seed.json` (Qdrant address, recording policy, S3, CPU/GPU execution provider, …). `vision-aio` fills **only the keys that are not in the database yet**, so values saved in the console always win. Edit the file *before the first start* if you want different defaults.
- **Secrets are automatic**: the signing key, internal token, admin JWT secret, viewer secret and session secret are generated on first boot and stored **encrypted** in MongoDB (the encryption key is derived from the MongoDB password). They are never shown in the console; you can replace or regenerate them there.
- ⚠ **Changing the MongoDB password** makes the stored secrets undecryptable — re-enter them in the console (auto-generated ones: press *Regenerate*; regenerating the signing key invalidates issued playback links).
- ⚠ **Upgrading from an older install**: the old `.env` values for these settings (secrets, Qdrant, recording, S3, AI keys, …) are **ignored**. Re-enter what you need in the console. If you stored face photos or camera passwords before, keep `VISION_SECRET_KEY` in `.env` for the first start after upgrading so they can still be decrypted (read-only), then remove it.

## Beginner tips

- Leave the defaults as they are if you are starting Vision for the first time.
- In shared mode, MongoDB / Redis / Qdrant credentials must match the root stack.
- Keep `VISION_STUDIO_SHARED=true` in shared deployments.
- Recording is `always` on by default. Set `VISION_RECORD_DEFAULT=off` if you do not need DVR recording.
- If the root sclab-proxy is not running on this host (e.g. a data-services-only server), add `tls` to `COMPOSE_PROFILES` so the bundled nginx (`vision-tls`) exposes ports 8890/8090/8080 directly. Do not enable it where sclab-proxy runs — the ports would conflict.
- Change the default MongoDB/Redis passwords before production — the server secrets are encrypted with a key derived from the MongoDB password.

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
