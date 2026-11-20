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
| `make-offline-update-zip.sh` | machine with internet (Linux or macOS) | builds a small **update bundle** with only the images you pick (e.g. `webapp`) - see section 8 |
| `update-offline-images.sh` | air-gapped server (root) | verifies and loads an update bundle and applies it to the installed system (rolling `webapp` update, health check, rollback, history) - see section 8 |

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
- **Update only some images** (for example `webapp` after a new release): build a small update bundle with
  `make-offline-update-zip.sh` and apply it with `update-offline-images.sh` - see section 8 (rolling update, rollback, history).
- **Update everything**: build a new full bundle with `make-offline-zip.sh`, copy it, and run `install-offline.sh` again (new bundle name = new
  extraction directory, changed images are loaded). Because an existing `.init` keeps the old repository files, apply new
  compose/env files from `/opt/sclab/bundle-<name>/repo` by hand, then `./run.sh`. `update.sh` / `docker compose pull` are disabled offline.
- **Reconfigure**: delete `/opt/sclab/docker-images/.init`, restore the files from the bundle's `repo/` directory, and run `install-offline.sh` again.
- Add or remove optional services later: `sudo ./service-manage.sh` (only services whose images are loaded will start).

## 8. Update only some images (offline update)

Use this when the server is already installed and only a few images changed - typically **`webapp`** after a new SCLAB release.
Instead of building and copying the whole bundle (Docker, every image, ~GBs) again, you build a small **update bundle** that
contains just the images you pick. The configuration (`.env` files, `settings.json`, certificates, `data/`) of the server is not touched.
No license key and no Docker Engine are part of an update bundle.

```
 PC / server WITH internet                              air-gapped server
 ───────────────────────────                            ───────────────────────────
 ./make-offline-update-zip.sh  ──►  <name>.tar.gz.part*  ──►  sudo bash ./update-offline-images.sh
   (pick services, pull,             <name>.SHA256SUMS         (verify, extract, docker load, show changes,
    docker save, split)              <name>.MANIFEST.json       roll out, health check, history, rollback)
                                     update-offline-images.sh
```

### 8.1 Build the update bundle (machine with internet; Linux or macOS)

Run it from a checkout of this repository, like the full bundle (see section 3, including "Building the bundle on a Mac"):

```bash
./make-offline-update-zip.sh                      # interactive: Up/Down (or j/k) move, Space check, Enter confirm
# or unattended:
./make-offline-update-zip.sh --yes --services webapp,ai-service --out ./sclab-update-out
```

The menu lists all services (the five required ones included); `webapp` is checked by default. Without a terminal a numeric
prompt is used. The script installs the AWS CLI if it is missing, logs in to ECR, runs `docker pull --platform linux/amd64` and
`docker save` for the selected images only, and writes a compressed archive split into 1 GB parts.

| Option | Meaning |
|---|---|
| `--services LIST` | comma separated services, e.g. `webapp,mail` (`--list-services` shows them all) |
| `--arch x86_64` | target CPU architecture (default and only supported value for now; `aarch64` is refused) |
| `--out DIR` | output directory (default `./sclab-update-out`) |
| `--name NAME` | bundle name (default `sclab-update-<YYYYMMDD-HHMMSS>-<arch>`) |
| `--part-size MB` | size of each part (default 1024) |
| `--with-compose` | also pack this repository's compose / script / config files (see 8.3); default is images only |
| `--base-bundle NAME` / `--base-manifest FILE` | record which full bundle this update belongs to (shown / checked on the server) |
| `--no-pull` | use the images that already exist locally (no AWS CLI, no ECR login) |

Every output file starts with the bundle name, so you can build several update bundles into the **same** output directory
without mixing them up:

```
sclab-update-20261120-153045-x86_64.tar.gz.part001   (... .part002 ...)
sclab-update-20261120-153045-x86_64.SHA256SUMS
sclab-update-20261120-153045-x86_64.MANIFEST.json     (kind, creation time, per image: tag / image ID / repo digest / size, services, architecture)
update-offline-images.sh                              (the same script for every bundle)
```

### 8.2 Copy the files to the server

Copy **all** files of the bundle (`<name>.*` and `update-offline-images.sh`) into **one directory** on the server (USB, `scp`, ...).
Files of several update bundles can sit in the same directory; each bundle is recognised by its name prefix.

### 8.3 Apply the update on the server

```bash
cd /path/to/the/copied/files
sudo bash ./update-offline-images.sh                # menu / confirmation
sudo bash ./update-offline-images.sh --yes --bundle sclab-update-20261120-153045-x86_64    # unattended
```

- The script looks at the current directory (or `--dir`) and lists the update bundles: name, date, services, size and status
  (`new` / `applied <date>`). With **one** bundle it only asks for a confirmation. With **several** bundles an arrow-key menu is shown
  (Up/Down move, **Enter** applies the highlighted one, or check several with **Space** and press Enter to apply them **in date order**).
  `--all` applies every bundle that was not applied yet, oldest first; `--bundle NAME[,NAME]` picks bundles without a menu.
- The installation is found automatically (the current directory if it has a `docker-compose.yml`, else `/opt/sclab/docker-images`);
  use `--install-dir DIR` otherwise.
- Steps: checksum verification (a damaged or missing part stops everything) → architecture check → the parts are joined and extracted to a
  temporary directory (next to the bundle, or `--work-dir`) → `docker load` → the new image IDs are compared with what the
  running containers use, and **only changed services** are listed → you confirm → the update is applied → health check.
- **Rollout:** `webapp` is replaced in a rolling way (the new container starts next to the old one, runs for 30 s, then the old one
  is stopped; `sclab-proxy` is restarted afterwards). Every other service is recreated with `docker compose up -d --no-deps <service>`.
  Nothing is pulled and no registry is contacted (offline mode / `pull_policy: never`).
- A service is considered healthy when its container is running (and `healthy` if it has a health check) and stays up for a few seconds.
  If the new webapp container does not become healthy, the old one keeps running and the new one is removed.
- **Before** anything changes, the images that ran so far are kept as `<repository>:rollback-<time>` tags and a rollback record is
  written to `<install dir>/.offline-updates/<bundle>/`. These tags are never pruned; remove them yourself with `docker image rm <tag>` when no longer needed.
- **Config files (bundles made with `--with-compose`):** the new compose / script files are compared with your installed copy and
  merged: files you never changed are replaced, files you changed are 3-way merged (your values win; on a conflict your file is kept and the new version is written next to it as `<file>.upstream`),
  new files are added. `*.env`, `settings.json`, `cert/`, `jwt/`, `data/`, `.init` and `.offline` are **never** overwritten. The differences are shown and you confirm first
  (`--no-config` skips this part). The replaced files are backed up under `.offline-updates/<bundle>/config-backup/`.
- `--dry-run` only verifies the checksums and shows what would change; `--list` only lists the bundles.

Example (two bundles in the directory, the second one checked in the menu):

```
$ sudo bash ./update-offline-images.sh
[ ok ] Found 2 update bundle(s) in /srv/updates:
  sclab-update-20261118-101500-x86_64
      2026-11-18T01:15:03 | webapp | 1.2 GB | applied 2026-11-18
  sclab-update-20261120-153045-x86_64
      2026-11-20T06:30:58 | webapp,mail | 1.5 GB | new
...
== Changes in sclab-update-20261120-153045-x86_64 ==
  SERVICE   IMAGE                    RUNNING       NEW           ACTION
  webapp    onpremise-webapp:latest   510fb0d29314  b329f6a69817  UPDATE (rolling, no downtime)
  mail      postfix:5.2.1             4e07dabae3fb  4e07dabae3fb  unchanged
Apply sclab-update-20261120-153045-x86_64 now? (1 service(s) will be restarted) [Y/n]:
```

### 8.4 Roll back

```bash
sudo bash ./update-offline-images.sh --rollback            # the most recently applied bundle
sudo bash ./update-offline-images.sh --rollback <bundle-name>
```

The previous images are tagged back, the services are recreated from them and the config files the update changed are restored.
If the health check fails during an update, you are asked whether to roll back right away (with `--yes` it happens
automatically; `--no-auto-rollback` turns that off).

### 8.5 History and duplicate detection

Every run is recorded in `<install dir>/.offline-updates/history.tsv` (time, bundle, `applied` / `failed` / `rolled-back`).
If you select a bundle that is already applied, the script tells you when it was applied and asks whether to apply it again
(`--yes` skips it, `--force` applies it again). A rolled-back bundle can be applied again.

### 8.6 Troubleshooting (update)

| Message / symptom | Cause / fix |
|---|---|
| `No update bundle found in ...` | run the script in the directory with the files, or use `--dir`; the `<name>.MANIFEST.json` files must be there |
| `Missing bundle file(s): ...` | a part was not copied; copy every `<name>.tar.gz.partNNN` next to `<name>.SHA256SUMS` |
| `Checksum verification FAILED` | a file was damaged in transfer; copy that file again. Nothing was changed |
| `Architecture mismatch` | the bundle was built for another CPU architecture; rebuild it with `--arch` for this server |
| `Several update bundles found and no terminal` | use `--bundle NAME` or `--all` for unattended runs |
| `Could not find the installed docker-images directory` | run the script from the install directory or pass `--install-dir /opt/sclab/docker-images` |
| `Not enough free disk space ...` | free space, or use `--work-dir` on a bigger disk (the images are also loaded into Docker's data directory) |
| `... failed its health check` | the old webapp keeps running; read the logs shown, fix the cause, or roll back (8.4) |
| `CONFLICT <file>` (config merge) | you and the bundle changed the same lines; merge `<file>.upstream` into `<file>` by hand and delete the `.upstream` file |

## 9. Troubleshooting

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
