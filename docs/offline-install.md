# Offline (air-gapped) installation guide

> Korean version: [offline-install-ko.md](offline-install-ko.md) · Back to the [README](../README.md)

This guide installs SCLAB Studio on a server that has **no internet access** (no Docker repositories, no GitHub, no AWS/ECR).
Everything the server needs - Docker Engine, Docker Compose, all container images, this repository and your license key -
is packed on a machine **with** internet access into a few split files. You copy those files to the server and run one script.

```
 PC / server WITH internet                         air-gapped server
 ───────────────────────────                       ───────────────────────────
 ./make-offline-zip.sh   ──►  *.part001 ...   ──►   sudo bash ./install-offline.sh
   (pull images, Docker,       SHA256SUMS            (verify, extract, install Docker,
    license, split 1 GB)       MANIFEST.json          docker load, install.sh, start)
                               install-offline.sh
```

## 1. Overview

| Script | Where | What it does |
|---|---|---|
| `make-offline-zip.sh` | machine with internet (any Linux) | asks for the target OS/architecture and the services, installs the AWS CLI if missing, logs in to ECR, downloads Docker Engine + Compose, runs `docker pull` + `docker save` for every selected image, packs everything (plus the license key) into one archive split into 1 GB parts, writes `SHA256SUMS` and `MANIFEST.json` |
| `install-offline.sh` | air-gapped server (root) | verifies the checksums, joins and extracts the parts, installs Docker + Compose from the bundle (unless Docker is already installed), `docker load`s the images, runs `install.sh --offline` (license key read from the bundle) and starts the services |

Design notes

- **Docker is installed from static binaries** (`download.docker.com/linux/static`), not from `.deb`/`.rpm` packages. A package set
  depends on the exact distribution release (containerd.io, iptables, container-selinux, ...) and cannot be resolved without
  the OS repositories; the static tarball is one self-contained set of binaries per CPU architecture that works on every
  distribution. The OS family you choose in the menu is only used to pick the right service manager (systemd / OpenRC) and to
  print warnings.
- **Images are pinned by what you pulled.** Every image is exported with `docker save`; `MANIFEST.json` records the tag,
  image ID and repo digest of each one. The bundled compose files get `pull_policy: never`, so Compose always uses the loaded
  images and never contacts a registry (a `latest` tag therefore means "the image that was in the bundle").
- The AWS CLI, ECR login, `docker compose pull`, Docker/Compose download and `git` are **never** used on the server.

## 2. What you need

On the machine with internet access (Linux, x86_64 or aarch64):

- `bash`, `tar`, `gzip`, `split`, `sha256sum`, `curl` or `wget`, and Docker (the script offers to install it with the OS package manager if missing)
- AWS credentials for the SCLAB ECR registry (provided by SCLAB support) - only needed if images are pulled from ECR; the AWS CLI is installed automatically if missing
- the SCLAB **license key** (a text string; it ends up in `settings.json` under `private.license`)
- free disk space of about **2.5 x the total image size** (the required services are roughly 1.5 GB; the tile server alone is ~95 GB)

On the air-gapped server (root access):

- Linux with the **same CPU architecture** as the bundle, `bash`, `tar`, `gzip`, `sha256sum`, `openssl`, `awk`, `sed`, `grep`, and `iptables` or `nftables`
- free disk space of about the bundle size (extraction) **plus** the image size (Docker data directory, usually `/var/lib/docker`)

## 3. Step 1 - build the bundle (machine with internet)

```bash
git clone https://github.com/sclab-io/docker-images.git
cd docker-images
./make-offline-zip.sh
```

The script is interactive:

1. **Target OS family** and **CPU architecture** (menus).
2. **Services** - a checkbox menu. Type a number to toggle, `a` = all, `n` = none, Enter = continue.
   `mongo redis webapp sclab-proxy mail` are always included. Optional: `qdrant ai-service node-vm-service sclab-agent gis-process
   mqtt-client mqtt-broker kafka-client tileserver gotenberg vision vision-gpu ollama vllm speaches`.
   Unselected services are not pulled **and** are removed from the bundled `docker-compose.yml`.
3. **License key** (hidden input) - stored as `license/LICENSE.key` (mode 600) inside the bundle and applied automatically on the server.
4. AWS CLI install / `aws configure` / ECR login if needed, then pull, save, compress and split.

Non-interactive example:

```bash
./make-offline-zip.sh --yes --os ubuntu --arch x86_64 \
  --services qdrant,ai-service,node-vm-service,gotenberg \
  --license-file ./my-license.txt --out ./sclab-offline-out
```

All options: `./make-offline-zip.sh --help` (`--list-services` prints the catalog; `--part-size MB`, `--no-license`,
`--docker-version`, `--compose-version`, `--work-dir`, `--no-pull` to use images that already exist locally).

Result (excerpt of a real run, sample bundle with 100 MB parts):

```
[info] Target: OS family=alpine, architecture=x86_64 (linux/amd64)
[info] Services in the bundle: mongo redis webapp sclab-proxy mail
[info] Removing unselected services from the bundled docker-compose.yml: qdrant ai-service node-vm-service sclab-agent gis-process mqtt-client mqtt-broker kafka-client
[info] Setting pull_policy: never in the bundled compose files
[info] Downloading Docker Engine 28.5.2 (x86_64)
[info] Downloading Docker Compose v2.40.3 (x86_64)
[ ok ] Docker Compose checksum verified
[info] [3/5] docker save mongo:8.2.7
[ ok ] License key stored in the bundle (license/LICENSE.key, mode 600)
[info] Creating the archive and splitting it into 100 MB parts (compressor: gzip)
[ ok ] 7 part(s) written
[ ok ] SHA256SUMS written
```

Files to upload (everything in the output directory):

```
sclab-offline-20261120-x86_64.tar.gz.part001 ... .part00N   (1 GB each by default)
SHA256SUMS            checksums of the parts, MANIFEST.json and install-offline.sh
MANIFEST.json         bundle name, target OS/arch, Docker/Compose versions, selected services,
                      every image (tag, image id, repo digest, size) and the part list
install-offline.sh    the installer (a copy is also inside the archive)
```

> The license key is stored **in plain text** inside the archive. Treat the files as confidential.

## 4. Step 2 - move the files to the server

Copy **all** files into one directory on the server (USB disk, internal file share, `scp` through a jump host, ...).
Verifying the copy is optional here - `install-offline.sh` verifies everything again - but it is a quick way to find a bad transfer:

```bash
cd /path/to/bundle
sha256sum -c SHA256SUMS
```

```
sclab-offline-20261120-x86_64.tar.gz.part001: OK
...
MANIFEST.json: OK
install-offline.sh: OK
```

## 5. Step 3 - install on the server

```bash
cd /path/to/bundle
sudo bash ./install-offline.sh          # interactive (install.sh questions: domain, passwords, ...)
# or unattended with all defaults (auto-generated passwords, default domain):
sudo bash ./install-offline.sh --yes
```

The script runs these steps (each prints a `== n/7 ... ==` header):

| Step | Action |
|---|---|
| 1/7 | root, Linux, CPU architecture equals the bundle, free disk space, all parts present |
| 2/7 | `sha256sum -c SHA256SUMS` - a damaged or incomplete file stops the installation before anything is changed |
| 3/7 | joins the parts and extracts to `/opt/sclab/bundle-<name>` (streamed: no second full-size copy) |
| 4/7 | installs Docker Engine + Compose from the bundle (systemd unit, OpenRC service, or a background `dockerd` as fallback). **Skipped if Docker and Compose already work** |
| 5/7 | `docker load` for every image (images already present with the same ID are skipped); the extracted `.tar` files are then deleted to save disk (`--keep-images` keeps them) |
| 6/7 | copies the repository to `/opt/sclab/docker-images`, runs `install.sh --offline` with the license key from the bundle |
| 7/7 | `./run.sh` (`docker compose up -d`) and `docker compose ps` |

Options: `--dir DIR` (where the parts are), `--dest DIR` (default `/opt/sclab`), `--skip-docker` (require an existing Docker),
`--force-docker`, `--no-start`, `--yes`, `--keep-images`, `--reload-images`, `--help`.

In offline mode `install.sh` skips the AWS CLI installation, the AWS credentials and the ECR login, only offers the services
that are inside the bundle (they default to **Yes**), reads the license from the bundle, and generates the JWT key pair and
the self-signed TLS certificate with the server's `openssl` instead of the `alpine` key-generator container (which needs the internet).

Excerpt of a real unattended run:

```
== 4/7 Docker Engine + Compose ==
[info] Installing Docker 28.5.2 static binaries to /usr/local/bin
[ ok ] Docker installed: Docker version 28.5.2, build ecc6942
== 5/7 Loading container images ==
[info] [3/5] docker load: mongo:8.2.7 (906 MB)
[ ok ] All 5 images loaded
== 6/7 Installing SCLAB Studio ==
[info] The license key from the bundle will be applied automatically.
License key loaded from the bundle: /opt/sclab/bundle-sclab-offline-20261120-x86_64/license/LICENSE.key
Offline mode: skipping AWS CLI / AWS credentials / ECR login (images are loaded from the bundle).
 - settings.json: replaced 'LICENSE CODE HERE' with <license key>.
 - jwt/: generated JWT key pair.
== 7/7 Starting services ==
NAME                          IMAGE              ...   STATUS
mongo                         mongo:8.2.7              Up 3 seconds
redis                         redis:8.2.1              Up 3 seconds
mail                          bytemark/smtp            Up 3 seconds
docker-images-sclab-proxy-1   nginx:alpine3.18         Up 3 seconds
```

At the end of a normal `install.sh` run the **administrator e-mail and password** are printed - note them down.

## 6. Verify the installation

```bash
cd /opt/sclab/docker-images
sudo docker compose ps          # every service "Up"
sudo ./logs.sh                  # follow the logs
```

Open `https://<your domain>` (default placeholder `https://sclab-onprem`, mapped to 127.0.0.1 in `/etc/hosts`)
and log in with the administrator account printed by the installer. The self-signed certificate triggers a browser warning
unless you replace `cert/cert.pem` / `cert/privkey.pem` with your own.

Check that no registry is needed: `grep -c "pull_policy: never" docker-compose.yml` equals the number of services, and
`ls /opt/sclab/docker-images/.offline` exists (this marker disables ECR login in `run.sh`, `pull.sh`, `update.sh`).

## 7. Update / reinstall

- **Re-running** `install-offline.sh` is safe: verified checksums, extraction, Docker, loaded images and an existing
  configuration (`.init`) are detected and skipped; it only (re)starts the services.
- **Update**: build a new bundle with `make-offline-zip.sh`, copy it, and run `install-offline.sh` again (new bundle name = new
  extraction directory, changed images are loaded). Because an existing `.init` keeps the old repository files, apply new
  compose/env files from `/opt/sclab/bundle-<name>/repo` by hand, then `./run.sh`. `update.sh` / `docker compose pull` are disabled offline. *(In-place upgrade of an existing installation is not automated yet.)*
- **Reconfigure**: delete `/opt/sclab/docker-images/.init`, restore the files from the bundle's `repo/` directory, and run `install-offline.sh` again.
- Add or remove optional services later: `sudo ./service-manage.sh` (only services whose images are loaded will start).

## 8. Troubleshooting

| Message / symptom | Cause / fix |
|---|---|
| `Missing bundle file(s): ...` | a part was not copied; copy every `*.partNNN` next to `SHA256SUMS` |
| `Checksum verification FAILED` | a file was damaged in transfer; copy that file again. Nothing has been installed |
| `Architecture mismatch` | the bundle was built for another CPU architecture; rebuild with `--arch` |
| `Not enough disk space ...` | free space or use `--dest` on a bigger disk; Docker images also need space under `/var/lib/docker` |
| `Docker was installed but the daemon did not start` | `journalctl -u docker` (systemd) or `/var/log/dockerd.log`; check that `iptables`/`nft` exists and the kernel supports `overlay` |
| containers have no network | install `iptables` (or nftables) from your OS media; on RHEL-family with firewalld run `systemctl restart docker` after `firewalld` is up |
| `openssl` / `sed` / `awk` not found | install them from your OS media - they cannot be fetched offline |
| install.sh asks for the license | the bundle was built with `--no-license` (or an empty key); type it in |
| `ai-service ... Qdrant` problems | `ai-service` was selected without `qdrant`; rebuild the bundle with both |
| `vllm` does not start | its compose file runs `apt-get`/`pip` at start-up (needs the internet) and models are not part of the bundle |
| ollama / speaches have no models | models are not bundled; copy them to the server separately |

## 9. What was verified (and what was not)

Verified with real runs of these scripts:

- `make-offline-zip.sh` inside an **Alpine Linux** (BusyBox tools, musl) container with `--no-pull` and local images
  (mongo, redis, nginx, bytemark/smtp; the `webapp` image was a stand-in): service trimming, `pull_policy: never`, Docker +
  Compose download and Compose checksum verification, `docker save`, tar/gzip/split into numbered parts, `SHA256SUMS`, `MANIFEST.json`.
- `install-offline.sh` inside an **Ubuntu 22.04** privileged container with **no network interface** (`--network none`, DNS lookups fail):
  checksum verification, extraction, static Docker installation (the container has no systemd, so the background-`dockerd` fallback was used),
  `docker load`, `install.sh --offline --yes` with the license applied from the bundle, key generation, `docker compose up`, and a second run
  that skipped every finished step.
- Error paths (each stops before anything is installed): a damaged part (`sha256sum: WARNING: 1 computed checksum did NOT match` /
  `Checksum verification FAILED ...`), a missing part (`Missing bundle file(s): ...part003 ...`), an architecture mismatch
  (`Architecture mismatch: this server is 'x86_64' but the bundle was built for 'aarch64'`) and a non-root run (`Root privileges are required`).
- `shellcheck` is clean at warning level for `make-offline-zip.sh`, `install-offline.sh` and `install.sh`.

**Not verified** (no suitable environment): pulling from the real ECR registry and the automatic AWS CLI installation (the `--no-pull` path was
used), the systemd and OpenRC service units on real hosts, aarch64, RHEL/SUSE/Amazon Linux hosts, SELinux-enforcing hosts, 1 GB part size with a
multi-GB bundle (100 MB parts were used), the real `onpremise-*` images (a stand-in was used for webapp), GPU images, and the
Vision / Ollama / vLLM / Speaches / tile server add-ons. Whether the SCLAB application itself makes outbound calls (license server, telemetry, CDN, map tiles) is
inside the images and was **not** checked.
