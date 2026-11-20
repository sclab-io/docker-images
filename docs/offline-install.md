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

On the machine with internet access (Linux, or macOS Intel/Apple Silicon - see "Building the bundle on a Mac"):

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

1. **Target OS family** (arrow-key menu: Up/Down or `j`/`k` to move, Enter to select). The CPU architecture is fixed to x86_64 (amd64);
   **aarch64/arm64 is not supported yet** (`--arch aarch64` stops with an error).
2. **Services** - a checkbox menu. Up/Down (or `j`/`k`) move, **Space** toggles, `a` = all, `n` = none, **Enter** = continue.
   The required services are shown as locked and cannot be unchecked. Without a terminal (pipe/CI) or with `TERM=dumb` the script falls back to
   numbered prompts (type a number to toggle).
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

### Building the bundle on a Mac (Intel or Apple Silicon)

`make-offline-zip.sh` also runs on macOS (the bundle is always for a **Linux** server; `install-offline.sh` is Linux-only).

- Requirements: a running Docker engine (**Docker Desktop**, **OrbStack**, or **Colima**), Homebrew (optional, used to install the AWS CLI),
  the stock macOS tools (the script works with the default bash 3.2 and BSD tools). The AWS CLI is installed automatically
  if it is missing: `brew install awscli`, otherwise the official installer for the current user only (`~/.local/aws-cli`, no sudo).
- The **target** is what you pick in the menu / `--os` / `--arch`, not the Mac's own CPU. The menu defaults to x86_64 even on Apple Silicon.
  Images are pulled with `docker pull --platform linux/amd64` (or `linux/arm64`) and exported with `docker save --platform ...`; nothing of the
  other architecture is executed (no emulation). The Docker Engine tarball and the Compose binary for the server are only **downloaded** into the bundle,
  never installed on the Mac.
- Images are pulled into your local Docker engine and replace local tags of the same name. If the engine still holds a different-architecture
  variant of the same tag (for example your own arm64 `mongo:8.2.7`), a pull for the other architecture replaces it - pull it again afterwards if you need it.
- Disk: the images are stored once inside the Docker VM and once more as staging files in `<out>/.work` on the Mac, plus the final parts
  (about 2.5 x the image size in total on the Mac, plus the images in the Docker VM; raise the Docker Desktop disk limit if needed).
- Use an x86_64 build for the current SCLAB images: `onpremise-webapp` is still published for amd64 only, so `--arch aarch64` stops with an error (currently not supported). The mail relay is multi-arch (`boky/postfix`, see below). Once a multi-arch `onpremise-webapp` is in ECR, aarch64 bundles become possible; until then they are not.
- The archives are created with root ownership and without macOS metadata (`._*` files / extended attributes), so they extract cleanly on Linux.

```bash
./make-offline-zip.sh                       # interactive
./make-offline-zip.sh --yes --os ubuntu --arch x86_64 --services none --license-file ./license.txt
```

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

### Choosing where the data is stored (separate disk)

`install-offline.sh` can put the two big data sets on another disk. Both questions are asked in an interactive run (**Enter = default**);
with `--yes` the options / environment variables or the defaults are used.

| What | Prompt default | Option / env | How it is applied |
|---|---|---|---|
| Docker data (images, containers, volumes) | `/var/lib/docker` | `--docker-data-root DIR` / `SCLAB_DOCKER_DATA_ROOT` | `"data-root"` is merged into `/etc/docker/daemon.json` (other keys are kept, the old file is backed up as `daemon.json.sclab-bak-<time>`) **before** dockerd starts, so `docker load` already writes there. systemd, OpenRC and the plain fallback start dockerd without `--data-root`, so all read this file. Docker Root Dir is verified with `docker info` at the end. |
| Application data (MongoDB, Redis, Qdrant, uploads, logs) | `<dest>/docker-images/data` | `--data-dir DIR` / `SCLAB_DATA_DIR` | `<dest>/docker-images/data` becomes a **symlink** to `DIR`. Every script and compose file keeps using `./data/...`, so run.sh, update.sh, logs.sh and the optional-services files work unchanged and the setting survives updates. |

Notes:

- Use an absolute path on a **mounted** disk. Mount it first (and add it to `/etc/fstab`), otherwise the data lands on the root disk;
  the script shows the filesystem, mount point and free space and warns when the path is on `/`, on NFS/CIFS/FUSE, or (Docker) on a `noexec`/`nosuid`/`nodev` mount.
  It stops when the Docker disk is smaller than the images need (MANIFEST `images_bytes` x 1.2).
- SELinux (enforcing): label the directories, e.g. `semanage fcontext -a -e /var/lib/docker /data/docker && restorecon -R /data/docker`
  (Docker) and `semanage fcontext -a -t container_file_t '/data/sclab(/.*)?' && restorecon -R /data/sclab` (application data). The script prints the matching commands.
- Permissions: the directory must be writable by root; containers create and `chown` their sub-directories themselves. Do not use an NFS export with root-squash.
- Docker **already installed**: its current data directory is shown and left alone. If you ask for another one, the script explains that existing images,
  containers and volumes would disappear from view, asks for confirmation (unattended runs keep the old directory); `--migrate-docker-data` stops Docker and
  copies the old directory (rsync or `cp -a`) to the new one - the old copy is not deleted.
- An existing `<dest>/docker-images/data` with content, or an existing link to another place, is never replaced or moved automatically.
- Re-running with the same values changes nothing.
- Without `jq`/`python3` the merge uses `sed`/`awk` (fine for typical `daemon.json` files; the result is checked by Docker itself when it starts).

```bash
sudo bash ./install-offline.sh --yes --docker-data-root /data/docker --data-dir /data/sclab
```

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

All tests ran in Docker (Docker Desktop, x86_64 host). Servers were simulated by privileged containers **without network access**
(`--network none`), which is why the installer never touched the internet in any of them.

| Item | Method | Result |
|---|---|---|
| Real ECR images + AWS CLI auto-install | `make-offline-zip.sh` in a bare `ubuntu:24.04` container (no curl, unzip, aws), real AWS credentials | missing tools and the AWS CLI were installed automatically, ECR login and real `onpremise-webapp` pull worked, real 1 GiB parts were produced |
| AWS CLI on aarch64 | same, in a `linux/arm64` container (QEMU) | AWS CLI, Docker and Compose aarch64 downloads and ECR login worked |
| Offline install on 9 distributions | `install-offline.sh --yes`, bundle built with the real images | Ubuntu 22.04/24.04, Debian 12, Rocky 9, Alma 8/9, Fedora, Amazon Linux 2023, openSUSE Leap 15.6, Alpine 3.20: all installed and started mongo, redis, mail, webapp and sclab-proxy |
| systemd service | systemd containers (Ubuntu 24.04, Debian 12), `docker restart` as "reboot" | unit registered and enabled, Docker and all containers came back by themselves, a second run skipped finished steps |
| OpenRC | Alpine with OpenRC | service registered, Docker started by OpenRC, installation completed |
| macOS build (Intel Mac, bash 3.2, Docker Desktop) | `make-offline-zip.sh` run on a Mac with real ECR images, then installed in an isolated Linux amd64 container | bundle built (real 1 GiB part), `install-offline.sh` verified the checksums and installed; 5 services up; files extracted as root. The interactive menu, Docker-not-running and no-Docker messages were checked. The no-sudo AWS CLI `.pkg` install method was checked by hand (not through the script, since `aws` was already installed) |
| Error paths | damaged part, missing part, wrong architecture, not root | each stops before anything is installed with a clear message |
| shellcheck | warning level | clean |

Things the tests found and fixed: `make-offline-zip.sh` stopped on machines without `curl`/`unzip` (now installs missing tools), the OpenRC
service shared a pid file with `dockerd` and failed to start, init-system failures ended the script silently, and a bundle was built even
when an image does not exist for the target architecture (now an error).

**Limits / not verified**

- **aarch64 bundles are not possible yet**: `onpremise-webapp` is published for amd64 only (no arm64 image in ECR so far), so `make-offline-zip.sh --arch aarch64` stops.
  The menu does not offer aarch64; `SCLAB_OFFLINE_ARM64=1` lifts the block for testing. In that mode the script checks every selected image for a `linux/arm64` manifest *before pulling*
  (`docker manifest inspect`) and stops naming each image that lacks one (this is exactly what happens with `onpremise-webapp` today). Only the images of the selected services are checked.
  Checked so far: the aarch64 tooling downloads, and `mongo`, `redis`, `nginx`, `boky/postfix` all have arm64 manifests.
- **Mail relay image**: the `mail` service now uses the multi-arch `boky/postfix:5.2.1` (amd64+arm64) instead of the amd64-only `bytemark/smtp`. It listens on port 25 and relays/delivers outgoing mail itself
  like before (`MAIL_URL=smtp://mail:25`). To keep the old image on an existing amd64 install set `MAIL_IMAGE=bytemark/smtp` (e.g. in a `.env` file next to docker-compose.yml).
- **License and outbound access**: the tests used a fake license key. With it the `webapp` container restarts in a loop (also when the internet is available),
  and during the isolated run it repeatedly looked up `app.sclab.io`. That is probably the license check; it means **a real license may need
  access to that host, which an air-gapped server does not have**. This could not be confirmed without a valid key - please verify with a real license.
- Not verified on macOS: **Apple Silicon** hardware (the Mac used was Intel; the cross-architecture path was only exercised as an arm64 target on the Intel host (pull and inspect with `--platform`; the run stops at the architecture check), and `save --platform` only for the native amd64 target), OrbStack and Colima, `brew install awscli`.
- Not verified: SELinux-enforcing hosts (the test containers share the Docker Desktop VM kernel), real hardware / real boot sequences (containers were restarted, not rebooted),
  RHEL itself (Rocky/Alma were used), SUSE/Amazon Linux other than the versions above, the Vision / Ollama / vLLM / Speaches / tile server / Gotenberg add-ons,
  and starting `dockerd` under heavy CPU load (one parallel run of openSUSE hit containerd's start timeout; a re-run passed).
- Minimal container images lack some tools a real server has (for example `iptables`, `openssl`, `groupadd` on Amazon Linux minimal); the test images added
  `openssl`, `iptables`, `procps` and `hostname` the way a normal server install has them.
