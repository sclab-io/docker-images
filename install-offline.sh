#!/usr/bin/env bash
# install-offline.sh - install SCLAB Studio on an air-gapped (offline) Linux server from a bundle made by make-offline-zip.sh.
#
# Put this script, SHA256SUMS, MANIFEST.json and all *.part001 ... files in ONE directory on the server, then run (as root):
#     sudo bash ./install-offline.sh
#
# What it does (no internet access is used at any point):
#   1. checks root, OS/architecture, free disk space
#   2. verifies the checksums (SHA256SUMS) of every part
#   3. joins the parts and extracts the bundle
#   4. installs Docker Engine + Compose from the bundle (skipped when Docker is already installed)
#   5. loads the container images (docker load)
#   6. installs the SCLAB repository files and runs install.sh in offline mode (license key read from the bundle)
#   7. starts the services (./run.sh)
# It is safe to run again: finished steps are detected and skipped.
set -euo pipefail

# ----------------------------------------------------------------------------- defaults
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/opt/sclab"
SKIP_DOCKER=0
FORCE_DOCKER=0
NO_START=0
ASSUME_YES=0
KEEP_IMAGES=0
RELOAD_IMAGES=0

if [ -t 1 ]; then C_G=$'\033[0;32m'; C_Y=$'\033[0;33m'; C_R=$'\033[0;31m'; C_B=$'\033[0;34m'; C_0=$'\033[0m'; else C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""; fi
info() { printf '%s\n' "${C_B}[info]${C_0} $*"; }
ok()   { printf '%s\n' "${C_G}[ ok ]${C_0} $*"; }
warn() { printf '%s\n' "${C_Y}[warn]${C_0} $*" >&2; }
err()  { printf '%s\n' "${C_R}[error]${C_0} $*" >&2; }
die()  { err "$*"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
step() { printf '\n%s\n' "${C_B}== $* ==${C_0}"; }

usage() {
  cat <<'EOF'
install-offline.sh - install SCLAB Studio from an offline bundle (no internet needed)

Usage: sudo bash ./install-offline.sh [options]

  --dir DIR           Directory that holds the *.part files, SHA256SUMS, MANIFEST.json (default: this script's directory)
  --dest DIR          Install location (default: /opt/sclab). The app goes to <dest>/docker-images.
  --skip-docker       Do not install Docker; require an existing Docker + Compose.
  --force-docker      Install the bundled Docker even if a Docker is already present.
  --no-start          Install and configure but do not start the services.
  -y, --yes           Unattended: accept the default answer to every install.sh question
                      (auto-generated passwords, default domain, ...). The generated admin password is printed at the end.
  --keep-images       Keep the extracted image tar files after loading (they are deleted by default to save disk space).
  --reload-images     Load the images again even if a previous run already did.
  -h, --help          Show this help.

Re-running is safe. If <dest>/docker-images is already configured (.init exists) its configuration is kept.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) SRC_DIR="$(cd "${2:?--dir needs a value}" && pwd)"; shift ;;
    --dest) DEST="${2:?--dest needs a value}"; shift ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    --force-docker) FORCE_DOCKER=1 ;;
    --no-start) NO_START=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    --keep-images) KEEP_IMAGES=1 ;;
    --reload-images) RELOAD_IMAGES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# ----------------------------------------------------------------------------- 1. checks
step "1/7 System checks"
[ "$(uname -s)" = "Linux" ] || die "This installer supports Linux only (detected: $(uname -s))."
[ "$(id -u)" -eq 0 ] || die "Root privileges are required. Run: sudo bash ./install-offline.sh"
for c in tar gzip sed awk grep df cat; do
  command_exists "$c" || die "Required command not found: $c"
done
if command_exists sha256sum; then SHA_CHECK="sha256sum -c"
elif command_exists shasum; then SHA_CHECK="shasum -a 256 -c"
else die "sha256sum (or shasum) is required to verify the bundle."; fi

[ -f "$SRC_DIR/MANIFEST.json" ] || die "MANIFEST.json not found in $SRC_DIR. Copy ALL files of the bundle into one directory (or use --dir)."
[ -f "$SRC_DIR/SHA256SUMS" ] || die "SHA256SUMS not found in $SRC_DIR."

json_value() { # top-level "key": "value" / number / bool from the pretty-printed MANIFEST.json
  sed -n "s/^  \"$1\": \"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\}\$/\1/p" "$SRC_DIR/MANIFEST.json" | head -1
}
BUNDLE_NAME="$(json_value bundle_name)"
TARGET_ARCH="$(json_value target_arch)"
TARGET_OS="$(json_value target_os)"
IMAGES_BYTES="$(json_value images_bytes)"
DOCKER_VERSION="$(json_value docker_version)"
[ -n "$BUNDLE_NAME" ] && [ -n "$TARGET_ARCH" ] || die "MANIFEST.json is damaged (bundle_name / target_arch missing)."
IMAGES_BYTES="${IMAGES_BYTES:-0}"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in x86_64|amd64) HOST_ARCH=x86_64 ;; aarch64|arm64) HOST_ARCH=aarch64 ;; esac
[ "$HOST_ARCH" = "$TARGET_ARCH" ] || die "Architecture mismatch: this server is '$HOST_ARCH' but the bundle was built for '$TARGET_ARCH'. Build a bundle for this server with make-offline-zip.sh."

DISTRO_ID="unknown"; DISTRO_LIKE=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  DISTRO_ID="$(. /etc/os-release; echo "${ID:-unknown}")"
  DISTRO_LIKE="$(. /etc/os-release; echo "${ID_LIKE:-}")"
fi
HOST_FAMILY=generic
case " $DISTRO_ID $DISTRO_LIKE " in
  *" ubuntu "*|*" debian "*) HOST_FAMILY=ubuntu ;;
  *" amzn "*) HOST_FAMILY=amzn ;;
  *" rhel "*|*" centos "*|*" fedora "*|*" rocky "*|*" almalinux "*|*" ol "*) HOST_FAMILY=rhel ;;
  *" suse "*|*" sles "*|*" opensuse"*) HOST_FAMILY=suse ;;
  *" alpine "*) HOST_FAMILY=alpine ;;
esac
if [ "$TARGET_OS" != "generic" ] && [ "$HOST_FAMILY" != "generic" ] && [ "$HOST_FAMILY" != "$TARGET_OS" ]; then
  warn "The bundle was prepared for OS family '$TARGET_OS' but this server looks like '$HOST_FAMILY' ($DISTRO_ID). The bundled Docker is a static build, so this usually still works."
fi
ok "Bundle: $BUNDLE_NAME | arch: $TARGET_ARCH | OS family: $TARGET_OS | server: $DISTRO_ID/$HOST_ARCH"

# parts listed in SHA256SUMS
PARTS="$(awk '{print $2}' "$SRC_DIR/SHA256SUMS" | sed 's/^\*//' | grep '\.part[0-9]*$' || true)"
[ -n "$PARTS" ] || die "No *.part files are listed in SHA256SUMS."
missing=""
for p in $PARTS; do [ -f "$SRC_DIR/$p" ] || missing="$missing $p"; done
[ -z "$missing" ] || die "Missing bundle file(s):$missing - copy every part into $SRC_DIR."

parts_bytes=0
for p in $PARTS; do
  sz="$(wc -c < "$SRC_DIR/$p" | tr -d ' ')"
  parts_bytes=$((parts_bytes + sz))
done
# Extraction needs about the (poorly compressible) archive size again, then docker load needs the images size in Docker's data dir.
mkdir -p "$DEST"
need_dest_kb=$(( parts_bytes / 1024 * 11 / 10 + 1048576 ))
have_dest_kb="$(df -Pk "$DEST" | awk 'NR==2 {print $4}')"
DOCKER_ROOT="/var/lib/docker"
[ -d "$DOCKER_ROOT" ] || DOCKER_ROOT="/var/lib"
need_docker_kb=$(( IMAGES_BYTES / 1024 * 12 / 10 ))
dest_dev="$(df -Pk "$DEST" | awk 'NR==2 {print $1}')"
docker_dev="$(df -Pk "$DOCKER_ROOT" | awk 'NR==2 {print $1}')"
if [ "$dest_dev" = "$docker_dev" ]; then
  need_dest_kb=$((need_dest_kb + need_docker_kb))
else
  have_docker_kb="$(df -Pk "$DOCKER_ROOT" | awk 'NR==2 {print $4}')"
  [ "$have_docker_kb" -ge "$need_docker_kb" ] || die "Not enough disk space for Docker images in $DOCKER_ROOT: need about $((need_docker_kb / 1024 / 1024)) GB, free $((have_docker_kb / 1024 / 1024)) GB."
fi
BUNDLE_DIR="$DEST/bundle-$BUNDLE_NAME"
if [ ! -f "$BUNDLE_DIR/.extracted" ]; then
  [ "$have_dest_kb" -ge "$need_dest_kb" ] || die "Not enough disk space in $DEST: need about $((need_dest_kb / 1024 / 1024)) GB, free $((have_dest_kb / 1024 / 1024)) GB. Use --dest on a bigger disk."
fi
ok "Disk space OK"

# ----------------------------------------------------------------------------- 2. checksums
step "2/7 Verifying checksums"
if [ -f "$BUNDLE_DIR/.extracted" ]; then
  info "Bundle already extracted in $BUNDLE_DIR - checking only the small files."
  ( cd "$SRC_DIR" && grep -v '\.part[0-9]*$' SHA256SUMS | $SHA_CHECK - ) || die "Checksum mismatch for MANIFEST.json / install-offline.sh."
else
  info "Checking ${parts_bytes} bytes in $(echo "$PARTS" | wc -l | tr -d ' ') part(s) - this can take several minutes."
  if ! ( cd "$SRC_DIR" && $SHA_CHECK SHA256SUMS ); then
    die "Checksum verification FAILED. A file is damaged or incomplete - copy it to the server again. Nothing was installed."
  fi
fi
ok "All checksums match"

# ----------------------------------------------------------------------------- 3. extract
step "3/7 Extracting the bundle"
if [ -f "$BUNDLE_DIR/.extracted" ]; then
  ok "Already extracted: $BUNDLE_DIR"
else
  rm -rf "$BUNDLE_DIR"
  mkdir -p "$BUNDLE_DIR"
  info "Joining the parts and extracting to $BUNDLE_DIR"
  # shellcheck disable=SC2086
  ( cd "$SRC_DIR" && cat $PARTS ) | tar -xzf - -C "$BUNDLE_DIR" || { rm -rf "$BUNDLE_DIR"; die "Extraction failed (archive damaged or disk full)."; }
  : > "$BUNDLE_DIR/.extracted"
  ok "Extracted"
fi
[ -f "$BUNDLE_DIR/bundle.env" ] || die "bundle.env missing inside the bundle."
# shellcheck disable=SC1090,SC1091
. "$BUNDLE_DIR/bundle.env"

# ----------------------------------------------------------------------------- 4. Docker
step "4/7 Docker Engine + Compose"

docker_ready() { command_exists docker && docker info >/dev/null 2>&1; }
compose_ready() { docker compose version >/dev/null 2>&1 || command_exists docker-compose; }

write_systemd_unit() {
  cat > /etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Application Container Engine (SCLAB offline install)
After=network-online.target firewalld.service time-set.target
Wants=network-online.target

[Service]
Type=notify
Environment=PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable docker >/dev/null 2>&1 || true
  systemctl restart docker || warn "systemctl restart docker failed (see: journalctl -u docker)"
}

write_openrc_service() {
  cat > /etc/init.d/docker <<'EOF'
#!/sbin/openrc-run
description="Docker Application Container Engine (SCLAB offline install)"
command="/usr/local/bin/dockerd"
command_background=true
# not /run/docker.pid: dockerd writes its own pid file there and would refuse to start
pidfile="/run/dockerd-openrc.pid"
output_log="/var/log/docker.log"
error_log="/var/log/docker.log"
depend() {
  need net cgroups
  after firewall
}
EOF
  chmod +x /etc/init.d/docker
  rc-update add cgroups boot >/dev/null 2>&1 || true
  rc-service cgroups start >/dev/null 2>&1 || true
  rc-update add docker default >/dev/null 2>&1 || true
  rc-service docker restart || warn "rc-service docker restart failed (see /var/log/docker.log)"
}

install_docker_from_bundle() {
  local tgz="$BUNDLE_DIR/docker/docker-$DOCKER_VERSION.tgz" tmp
  [ -f "$tgz" ] || die "Docker archive not found in the bundle: $tgz"
  if command_exists iptables || command_exists nft || command_exists iptables-nft; then :
  else warn "Neither iptables nor nftables was found. Docker networking needs one of them; install it from your OS media if containers have no network."; fi

  info "Installing Docker $DOCKER_VERSION static binaries to /usr/local/bin"
  tmp="$(mktemp -d)"
  tar -xzf "$tgz" -C "$tmp"
  mkdir -p /usr/local/bin
  for f in "$tmp"/docker/*; do
    cp -f "$f" /usr/local/bin/ 2>/dev/null || { systemctl stop docker 2>/dev/null || true; cp -f "$f" /usr/local/bin/; }
    chmod 755 "/usr/local/bin/$(basename "$f")"
  done
  rm -rf "$tmp"

  mkdir -p /usr/local/lib/docker/cli-plugins
  cp -f "$BUNDLE_DIR/docker/docker-compose" /usr/local/lib/docker/cli-plugins/docker-compose
  chmod 755 /usr/local/lib/docker/cli-plugins/docker-compose

  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker 2>/dev/null || addgroup -S docker 2>/dev/null || warn "Could not create the 'docker' group."
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    usermod -aG docker "$SUDO_USER" 2>/dev/null || addgroup "$SUDO_USER" docker 2>/dev/null || true
  fi
  for m in overlay br_netfilter; do modprobe "$m" 2>/dev/null || true; done

  if [ -d /run/systemd/system ] && command_exists systemctl; then
    info "Registering the systemd service"
    write_systemd_unit
  elif command_exists rc-service && command_exists rc-update; then
    info "Registering the OpenRC service"
    write_openrc_service
  else
    warn "No systemd/OpenRC found: starting dockerd in the background. Add /usr/local/bin/dockerd to your init system to start it at boot."
    PATH="/usr/local/bin:$PATH" nohup /usr/local/bin/dockerd >/var/log/dockerd.log 2>&1 &
  fi

  local _
  for _ in $(seq 1 60); do
    docker info >/dev/null 2>&1 && break
    sleep 1
  done
  docker_ready || die "Docker was installed but the daemon did not start. Check: journalctl -u docker (or /var/log/dockerd.log)."
  ok "Docker installed: $(docker --version)"
}

if [ "$SKIP_DOCKER" = "1" ]; then
  docker_ready || die "--skip-docker was given but Docker is not installed or not running."
  compose_ready || die "--skip-docker was given but Docker Compose is not available (need 'docker compose' or docker-compose)."
  ok "Using the existing Docker: $(docker --version)"
elif [ "$FORCE_DOCKER" = "0" ] && command_exists docker; then
  if ! docker_ready; then
    info "Docker is installed but not running: trying to start it"
    if command_exists systemctl; then systemctl start docker 2>/dev/null || true; fi
    if command_exists rc-service; then rc-service docker start 2>/dev/null || true; fi
    for _ in $(seq 1 30); do docker_ready && break; sleep 1; done
    docker_ready || die "Docker is installed but its daemon is not running and could not be started. Start it, or run with --force-docker to reinstall from the bundle."
  fi
  if compose_ready; then
    ok "Docker already installed - skipping ($(docker --version))"
  else
    info "Docker is present but Compose is missing: installing the bundled Compose plugin"
    mkdir -p /usr/local/lib/docker/cli-plugins
    cp -f "$BUNDLE_DIR/docker/docker-compose" /usr/local/lib/docker/cli-plugins/docker-compose
    chmod 755 /usr/local/lib/docker/cli-plugins/docker-compose
    compose_ready || die "Docker Compose could not be installed."
    ok "Compose installed: $(docker compose version)"
  fi
else
  install_docker_from_bundle
  compose_ready || die "Docker Compose is not available after installation."
fi
if docker compose version >/dev/null 2>&1; then ok "Compose: $(docker compose version | head -1)"; fi

# ----------------------------------------------------------------------------- 5. load images
step "5/7 Loading container images"
if [ -f "$BUNDLE_DIR/.images-loaded" ] && [ "$RELOAD_IMAGES" = "0" ]; then
  ok "Images were already loaded by a previous run (use --reload-images to load again)."
else
  total="$(wc -l < "$BUNDLE_DIR/images.tsv" | tr -d ' ')"
  n=0
  while IFS="$(printf '\t')" read -r ref id fname _digest size _svcs; do
    [ -n "$ref" ] || continue
    n=$((n + 1))
    cur="$(docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null || true)"
    if [ "$RELOAD_IMAGES" = "0" ] && [ -n "$cur" ] && [ "$cur" = "$id" ]; then
      ok "[$n/$total] already present: $ref"
      continue
    fi
    [ -f "$BUNDLE_DIR/images/$fname" ] || die "Image file missing in the bundle: images/$fname (was it deleted? re-run with --reload-images after re-extracting)."
    info "[$n/$total] docker load: $ref ($((size / 1024 / 1024)) MB)"
    docker load -i "$BUNDLE_DIR/images/$fname" >/dev/null || die "docker load failed for $ref"
    docker image inspect "$ref" >/dev/null 2>&1 || die "After loading, image $ref is not present."
  done < "$BUNDLE_DIR/images.tsv"
  : > "$BUNDLE_DIR/.images-loaded"
  ok "All $total images loaded"
fi
if [ "$KEEP_IMAGES" = "0" ] && [ -d "$BUNDLE_DIR/images" ]; then
  info "Removing the extracted image tar files to save disk space (use --keep-images to keep them; the parts stay in $SRC_DIR)"
  rm -f "$BUNDLE_DIR"/images/*.tar
fi

# ----------------------------------------------------------------------------- 6. install SCLAB
step "6/7 Installing SCLAB Studio"
APP_DIR="$DEST/docker-images"
mkdir -p "$APP_DIR"
if [ -f "$APP_DIR/.init" ]; then
  ok "$APP_DIR is already configured (.init exists): keeping the existing configuration."
else
  info "Copying the repository files to $APP_DIR"
  ( cd "$BUNDLE_DIR/repo" && tar -cf - . ) | ( cd "$APP_DIR" && tar -xf - )
  chmod +x "$APP_DIR"/*.sh "$APP_DIR"/*/*.sh 2>/dev/null || true
  LICENSE_ARG=""
  if [ -f "$BUNDLE_DIR/license/LICENSE.key" ]; then
    LICENSE_ARG="$BUNDLE_DIR/license/LICENSE.key"
    info "The license key from the bundle will be applied automatically."
  else
    warn "The bundle contains no license key: install.sh will ask for it."
  fi
  export SCLAB_OFFLINE=1
  export SCLAB_LICENSE_FILE="$LICENSE_ARG"
  export SCLAB_BUNDLE_SERVICES="$SERVICES"
  cd "$APP_DIR"
  if [ "$ASSUME_YES" = "1" ]; then
    info "Unattended mode: running install.sh with the default answer to every question."
    # an endless stream of empty lines = "press Enter" for each prompt
    ./install.sh --offline < <(yes '') || die "install.sh failed."
  else
    ./install.sh --offline || die "install.sh failed."
  fi
  cd "$SRC_DIR"
fi

# ----------------------------------------------------------------------------- 7. start
step "7/7 Starting services"
case " $SERVICES " in
  *" vision "*) VISION_IN=1 ;;
  *) VISION_IN=0 ;;
esac
if [ "$NO_START" = "1" ]; then
  ok "--no-start given: not starting. Start later with: cd $APP_DIR && sudo ./run.sh"
else
  ( cd "$APP_DIR" && ./run.sh ) || die "Starting the services failed. See: cd $APP_DIR && docker compose ps && docker compose logs"
  sleep 3
  ( cd "$APP_DIR" && METEOR_SETTINGS="$(cat settings.json)" docker compose ps ) || true
  if [ "$VISION_IN" = "1" ] && [ -d "$APP_DIR/vision" ] && [ ! -f "$APP_DIR/vision/.env" ]; then
    info "Installing SCLAB Vision (offline mode)"
    vflag=""; [ "$ASSUME_YES" = "1" ] && vflag="-y"
    ( cd "$APP_DIR/vision" && SCLAB_OFFLINE=1 ./install.sh $vflag ) || warn "Vision installation failed; run it later: cd $APP_DIR/vision && SCLAB_OFFLINE=1 ./install.sh"
  fi
fi

echo
echo "================================================================"
echo " SCLAB Studio offline installation finished"
echo "================================================================"
echo " Install dir   : $APP_DIR"
echo " Check status  : cd $APP_DIR && docker compose ps"
echo " Logs          : cd $APP_DIR && sudo ./logs.sh"
echo " Stop / start  : sudo ./stop.sh  /  sudo ./run.sh"
case " $SERVICES " in
  *" ollama "*|*" speaches "*|*" vllm "*)
    echo " AI runtimes   : images are loaded but not started. Start e.g.: cd $APP_DIR/ollama && docker compose up -d"
    echo "                 Models are NOT part of the bundle: copy them to the server separately (see the repo README)." ;;
esac
echo " Offline note  : 'docker compose pull', update.sh and the ECR login are disabled (.offline marker)."
echo "                 To update, build a new bundle with make-offline-zip.sh and run install-offline.sh again."
