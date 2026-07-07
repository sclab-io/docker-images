#!/usr/bin/env bash
# SCLAB Vision installer — aio + console by default. Works on all major Linux distributions.
#   ./install.sh          Interactive, step-by-step (press Enter to accept the default at every prompt)
#   ./install.sh -y       Unattended — install with all defaults, no questions
#
# Network: sclab-network (shared with the sibling stack). Volumes: everything under ./data/vision/*.
set -euo pipefail

cd "$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE_BASE="docker-compose.yml"

# ─────────────────────────── output helpers ───────────────────────────
if [ -t 1 ]; then C_G="\033[0;32m"; C_Y="\033[0;33m"; C_R="\033[0;31m"; C_B="\033[0;34m"; C_0="\033[0m"; else C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""; fi
info() { printf "%b\n" "${C_B}▶${C_0} $*"; }
ok()   { printf "%b\n" "${C_G}✓${C_0} $*"; }
warn() { printf "%b\n" "${C_Y}⚠${C_0} $*"; }
err()  { printf "%b\n" "${C_R}✗${C_0} $*" >&2; }
die()  { err "$*"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

ASSUME_YES=0
for a in "$@"; do case "$a" in -y|--yes) ASSUME_YES=1 ;; -h|--help) sed -n '2,6p' "$0"; exit 0 ;; esac; done
# Interactive only when a TTY is available and -y was not given; otherwise use defaults.
if [ "$ASSUME_YES" = "1" ] || { [ ! -t 0 ] && [ ! -e /dev/tty ]; }; then INTERACTIVE=0; else INTERACTIVE=1; fi

ask() {  # $1=prompt $2=default → answer (Enter = default)
  local p="$1" d="$2" a=""
  if [ "$INTERACTIVE" = "0" ]; then echo "$d"; return; fi
  if [ -n "$d" ]; then printf "  %s [%s]: " "$p" "$d" >/dev/tty; else printf "  %s: " "$p" >/dev/tty; fi
  IFS= read -r a </dev/tty || a=""
  echo "${a:-$d}"
}
ask_yn() {  # $1=prompt $2=default(y|n) → 0=yes
  local p="$1" d="$2" a="" hint
  case "$d" in y|Y) hint="Y/n" ;; *) hint="y/N" ;; esac
  if [ "$INTERACTIVE" = "0" ]; then case "$d" in y|Y) return 0 ;; *) return 1 ;; esac; fi
  printf "  %s [%s]: " "$p" "$hint" >/dev/tty
  IFS= read -r a </dev/tty || a=""
  a="${a:-$d}"; case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
gen_secret() {  # random 48-char hex
  if command_exists openssl; then openssl rand -hex 24
  elif [ -r /dev/urandom ]; then LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 48
  else echo "sv$(date +%s)$$${RANDOM:-0}${RANDOM:-0}" | head -c 48; fi
}

# ─────────────────── distro detection + Docker install ───────────────────
detect_distro() {
  if [ -f /etc/os-release ]; then . /etc/os-release; DISTRO_ID="${ID:-unknown}"; else DISTRO_ID="unknown"; fi
}
install_docker() {
  info "Installing Docker (${DISTRO_ID})..."
  local SUDOCMD=""; [ "$(id -u)" -ne 0 ] && command_exists sudo && SUDOCMD="sudo"
  case "$DISTRO_ID" in
    ubuntu|debian|raspbian|linuxmint|pop)
      $SUDOCMD apt-get update -y
      $SUDOCMD apt-get install -y ca-certificates curl
      $SUDOCMD install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" | $SUDOCMD tee /etc/apt/keyrings/docker.asc >/dev/null 2>&1 || \
        curl -fsSL "https://download.docker.com/linux/debian/gpg" | $SUDOCMD tee /etc/apt/keyrings/docker.asc >/dev/null
      $SUDOCMD chmod a+r /etc/apt/keyrings/docker.asc
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | $SUDOCMD tee /etc/apt/sources.list.d/docker.list >/dev/null
      $SUDOCMD apt-get update -y
      $SUDOCMD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ;;
    fedora)
      $SUDOCMD dnf -y install dnf-plugins-core
      $SUDOCMD dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      $SUDOCMD dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      $SUDOCMD systemctl enable --now docker ;;
    centos|rhel|rocky|almalinux)
      $SUDOCMD yum install -y yum-utils
      $SUDOCMD yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      $SUDOCMD yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      $SUDOCMD systemctl enable --now docker ;;
    opensuse*|sles|suse)
      $SUDOCMD zypper install -y docker docker-compose; $SUDOCMD systemctl enable --now docker ;;
    arch|manjaro|endeavouros)
      $SUDOCMD pacman -Sy --noconfirm docker docker-compose; $SUDOCMD systemctl enable --now docker ;;
    alpine)
      $SUDOCMD apk add --no-cache docker docker-cli-compose; $SUDOCMD rc-update add docker default 2>/dev/null || true; $SUDOCMD service docker start 2>/dev/null || true ;;
    *)
      warn "Automatic install is not supported for '${DISTRO_ID}'. See https://docs.docker.com/engine/install/ then re-run."; return 1 ;;
  esac
}

# ─────────────────── Docker / Compose readiness ───────────────────
SUDO=""
ensure_docker() {
  detect_distro
  if ! command_exists docker; then
    warn "Docker is not installed."
    if ask_yn "Install Docker now?" y; then install_docker || die "Docker installation failed."; else die "Docker is required."; fi
  fi
  # Daemon access (permissions). Fall back to sudo if needed.
  if docker info >/dev/null 2>&1; then SUDO=""
  elif [ "$(id -u)" -ne 0 ] && command_exists sudo && sudo docker info >/dev/null 2>&1; then
    SUDO="sudo "; warn "Using sudo for the Docker daemon (add your user to the 'docker' group to avoid sudo)."
  else
    die "Cannot reach the Docker daemon. Check that it is running and that you have permission (docker group / sudo)."
  fi
  # Prefer compose v2 (plugin), fall back to v1.
  if ${SUDO}docker compose version >/dev/null 2>&1; then DC="${SUDO}docker compose"
  elif command_exists docker-compose; then DC="${SUDO}docker-compose"
  else die "docker compose (plugin) or docker-compose is required."; fi
  ok "Docker OK ($(${SUDO}docker --version 2>/dev/null | head -1)) · compose='${DC# }'"
}

ensure_network() {
  if ${SUDO}docker network inspect sclab-network >/dev/null 2>&1; then
    ok "Network sclab-network already exists"
  else
    info "Creating network sclab-network"
    ${SUDO}docker network create sclab-network >/dev/null && ok "sclab-network created"
  fi
}

# ═══════════════════════════ install flow ═══════════════════════════
printf "%b\n" "${C_G}╔══════════════════════════════════════════════╗${C_0}"
printf "%b\n" "${C_G}║        SCLAB Vision installer (aio + console)  ║${C_0}"
printf "%b\n" "${C_G}╚══════════════════════════════════════════════╝${C_0}"
[ "$INTERACTIVE" = "0" ] && info "Unattended mode — installing with defaults."

ensure_docker
ensure_network

# defaults
DEF_REGISTRY="873379329511.dkr.ecr.ap-northeast-2.amazonaws.com/sclabio"
GPU=0; DB_MODE="dedicated"; REC_MODE="off"
VISION_STUDIO_SHARED="false"
VISION_MONGO_URL="mongodb://vision-mongo:27017"; VISION_MONGO_DB="vision"; VISION_REDIS_URL="redis://vision-redis:6379"
VISION_CONSOLE_PORT="8890"; VISION_CONTROL_PORT="8090"; VISION_GATEWAY_PORT="8080"
VISION_REGISTRY="$DEF_REGISTRY"; VISION_TAG="latest"
VISION_S3_BUCKET=""; VISION_RECORD_DEFAULT="off"; VISION_HLS_CORS_ORIGINS="*"

echo; info "You'll be asked a few questions. ${C_Y}Press Enter to accept the default${C_0} shown in [brackets]."

# 1) accelerator
echo; printf "%b\n" "${C_B}[1/6] Accelerator${C_0}"
if ask_yn "Use an NVIDIA GPU? (default: CPU; requires nvidia-container-toolkit)" n; then GPU=1; fi

# 2) database
echo; printf "%b\n" "${C_B}[2/6] Database (Mongo/Redis)${C_0}"
echo "  1) Run Vision's own Mongo/Redis (default, self-contained)"
echo "  2) Share SCLAB Studio's mongo/redis (the mongo·redis already on sclab-network)"
db_choice="$(ask "Choose (1/2)" "1")"
if [ "$db_choice" = "2" ]; then
  DB_MODE="shared"; VISION_STUDIO_SHARED="true"
  VISION_MONGO_URL="$(ask "Mongo URL" "mongodb://root:changeThisMongoPassword@mongo:27017/?authSource=admin")"
  VISION_MONGO_DB="$(ask "Mongo DB name (usually 'sclab' when shared)" "sclab")"
  VISION_REDIS_URL="$(ask "Redis URL" "redis://:changeThisRedisPassword@redis:6379")"
fi

# 3) recording (DVR)
echo; printf "%b\n" "${C_B}[3/6] Recording (DVR)${C_0}"
echo "  1) Disabled (default)"
echo "  2) Record to disk (./data/vision/recordings)"
echo "  3) Disk + S3 object storage (RustFS cold tier)"
rec_choice="$(ask "Choose (1/2/3)" "1")"
case "$rec_choice" in
  2) REC_MODE="disk"; VISION_RECORD_DEFAULT="always" ;;
  3) REC_MODE="s3";   VISION_RECORD_DEFAULT="always"; VISION_S3_BUCKET="sv-recordings" ;;
  *) REC_MODE="off";  VISION_RECORD_DEFAULT="off" ;;
esac

# 4) ports
echo; printf "%b\n" "${C_B}[4/6] Exposed ports${C_0}"
VISION_CONSOLE_PORT="$(ask "Console web UI port" "$VISION_CONSOLE_PORT")"
VISION_GATEWAY_PORT="$(ask "HLS gateway port" "$VISION_GATEWAY_PORT")"
VISION_CONTROL_PORT="$(ask "Control API port" "$VISION_CONTROL_PORT")"

# 5) images
echo; printf "%b\n" "${C_B}[5/6] Images${C_0}"
VISION_REGISTRY="$(ask "Registry" "$VISION_REGISTRY")"
VISION_TAG="$(ask "Tag" "$VISION_TAG")"

# 6) secrets
echo; printf "%b\n" "${C_B}[6/6] Secrets (production security — 3 values shared by aio/console)${C_0}"
if ask_yn "Auto-generate secrets? (no = keep insecure dev defaults)" y; then
  VISION_INTERNAL_TOKEN="$(gen_secret)"; VISION_ADMIN_JWT_SECRET="$(gen_secret)"; VISION_SIGNING_KEY="$(gen_secret)"
  ok "Generated 3 random secrets"
else
  VISION_INTERNAL_TOKEN="sv-dev-internal-token"; VISION_ADMIN_JWT_SECRET="sv-dev-admin-jwt-secret"; VISION_SIGNING_KEY="dev-insecure-signing-key"
  warn "Using insecure dev secrets — do NOT expose in production."
fi

# ── assemble profiles / COMPOSE_FILE ──
PROFILES=""
[ "$DB_MODE" = "dedicated" ] && PROFILES="db"
[ "$REC_MODE" = "s3" ] && PROFILES="${PROFILES:+$PROFILES,}s3"
COMPOSE_FILE_LINE=""
DC_FILES=(-f "$COMPOSE_FILE_BASE")
if [ "$GPU" = "1" ]; then
  COMPOSE_FILE_LINE="COMPOSE_FILE=docker-compose.yml:docker-compose.gpu.yml"
  DC_FILES=(-f "$COMPOSE_FILE_BASE" -f "docker-compose.gpu.yml")
fi

# ── write .env ──
info "Saving configuration: .env"
{
cat <<EOF
# SCLAB Vision — generated by install.sh ($(date '+%Y-%m-%d %H:%M:%S')). Edit then run ./up.sh to apply.
COMPOSE_PROFILES=${PROFILES}
${COMPOSE_FILE_LINE}
VISION_REGISTRY=${VISION_REGISTRY}
VISION_TAG=${VISION_TAG}
VISION_CONSOLE_PORT=${VISION_CONSOLE_PORT}
VISION_CONTROL_PORT=${VISION_CONTROL_PORT}
VISION_GATEWAY_PORT=${VISION_GATEWAY_PORT}
VISION_MONGO_URL=${VISION_MONGO_URL}
VISION_MONGO_DB=${VISION_MONGO_DB}
VISION_REDIS_URL=${VISION_REDIS_URL}
VISION_STUDIO_SHARED=${VISION_STUDIO_SHARED}
VISION_INTERNAL_TOKEN=${VISION_INTERNAL_TOKEN}
VISION_ADMIN_JWT_SECRET=${VISION_ADMIN_JWT_SECRET}
VISION_SIGNING_KEY=${VISION_SIGNING_KEY}
VISION_HLS_CORS_ORIGINS=${VISION_HLS_CORS_ORIGINS}
VISION_RECORD_DEFAULT=${VISION_RECORD_DEFAULT}
VISION_RECORD_DELETE_AFTER=86400
VISION_S3_BUCKET=${VISION_S3_BUCKET}
VISION_S3_ENDPOINT=http://rustfs:9000
VISION_S3_REGION=us-east-1
VISION_S3_ACCESS_KEY_ID=rustfsadmin
VISION_S3_SECRET_ACCESS_KEY=rustfsadmin
VISION_S3_PREFIX=recordings
VISION_S3_API_PORT=9000
VISION_S3_CONSOLE_PORT=9001
RUST_LOG=info
EOF
} > .env
ok ".env written"

# ── data directories ──
info "Creating data directories under ./data/vision/"
mkdir -p data/vision/recordings
[ "$DB_MODE" = "dedicated" ] && mkdir -p data/vision/mongo data/vision/redis
[ "$REC_MODE" = "s3" ] && mkdir -p data/vision/rustfs
ok "Directories ready"

# ── ECR login (when the registry is ECR) ──
case "$VISION_REGISTRY" in
  *.dkr.ecr.*.amazonaws.com*)
    region="$(printf '%s' "$VISION_REGISTRY" | sed -n 's/.*\.dkr\.ecr\.\([a-z0-9-]*\)\.amazonaws\.com.*/\1/p')"
    host="$(printf '%s' "$VISION_REGISTRY" | sed -n 's#\(^[0-9]*\.dkr\.ecr\.[a-z0-9-]*\.amazonaws\.com\).*#\1#p')"
    if command_exists aws; then
      info "Logging in to ECR (${host})"
      if aws ecr get-login-password --region "$region" 2>/dev/null | ${SUDO}docker login --username AWS --password-stdin "$host" >/dev/null 2>&1; then
        ok "ECR login succeeded"
      else
        warn "ECR login failed — check your AWS credentials (aws configure/SSO). Continuing if images are already local."
      fi
    else
      warn "aws CLI not found — skipping ECR login. Pull may fail for private images."
    fi ;;
esac

# ── pull + up ──
echo; info "Pulling images"
${DC} "${DC_FILES[@]}" pull || warn "Some images failed to pull — continuing with any local images."
info "Starting containers (up -d)"
${DC} "${DC_FILES[@]}" up -d

# ── summary ──
HOSTIP="$(hostname -I 2>/dev/null | awk '{print $1}')"; [ -z "$HOSTIP" ] && HOSTIP="localhost"
echo
ok "Installation complete!"
printf "%b\n" "${C_G}────────────────────────────────────────────${C_0}"
printf "  Console web UI : ${C_B}http://%s:%s${C_0}\n" "$HOSTIP" "$VISION_CONSOLE_PORT"
printf "  Control API    : http://%s:%s\n" "$HOSTIP" "$VISION_CONTROL_PORT"
printf "  HLS gateway    : http://%s:%s\n" "$HOSTIP" "$VISION_GATEWAY_PORT"
[ "$REC_MODE" = "s3" ] && printf "  RustFS console : http://%s:9001 (rustfsadmin/rustfsadmin)\n" "$HOSTIP"
printf "%b\n" "${C_G}────────────────────────────────────────────${C_0}"
echo   "  Setup: aio+console · $( [ "$GPU" = 1 ] && echo GPU || echo CPU ) · db=${DB_MODE} · recording=${REC_MODE}"
echo   "  Status: ${DC# } ps    Logs: ./logs.sh    Stop: ./down.sh"
[ "$DB_MODE" = "shared" ] && warn "Shared DB mode: mongo/redis must already be running on sclab-network."
