#!/usr/bin/env bash
# SCLAB Vision stand-alone 설치 스크립트. 주요 Linux 배포판에서 동작한다.
#   ./install.sh          대화형 단계별 설치
#   ./install.sh -y       기본값으로 무인 설치
set -euo pipefail

cd "$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE_BASE="docker-compose.yml"
. ./_tls.sh

if [ -t 1 ]; then
  C_G="\033[0;32m"; C_Y="\033[0;33m"; C_R="\033[0;31m"; C_B="\033[0;34m"; C_0="\033[0m"
else
  C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""
fi
info() { printf "%b\n" "${C_B}>${C_0} $*"; }
ok()   { printf "%b\n" "${C_G}OK${C_0} $*"; }
warn() { printf "%b\n" "${C_Y}WARN${C_0} $*"; }
err()  { printf "%b\n" "${C_R}ERR${C_0} $*" >&2; }
die()  { err "$*"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
  esac
done

if [ "$ASSUME_YES" = "1" ] || { [ ! -t 0 ] && [ ! -e /dev/tty ]; }; then
  INTERACTIVE=0
else
  INTERACTIVE=1
fi

ask() {
  local p="$1" d="$2" a=""
  if [ "$INTERACTIVE" = "0" ]; then echo "$d"; return; fi
  if [ -n "$d" ]; then
    printf "  %s [%s]: " "$p" "$d" >/dev/tty
  else
    printf "  %s: " "$p" >/dev/tty
  fi
  IFS= read -r a </dev/tty || a=""
  echo "${a:-$d}"
}

ask_yn() {
  local p="$1" d="$2" a="" hint
  case "$d" in y|Y) hint="Y/n" ;; *) hint="y/N" ;; esac
  if [ "$INTERACTIVE" = "0" ]; then
    case "$d" in y|Y) return 0 ;; *) return 1 ;; esac
  fi
  printf "  %s [%s]: " "$p" "$hint" >/dev/tty
  IFS= read -r a </dev/tty || a=""
  a="${a:-$d}"
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

gen_secret() {
  if command_exists openssl; then
    openssl rand -hex 24
  elif [ -r /dev/urandom ]; then
    LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 48
  else
    echo "sv$(date +%s)$$${RANDOM:-0}${RANDOM:-0}" | head -c 48
  fi
}

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
  else
    DISTRO_ID="unknown"
  fi
}

install_docker() {
  info "Installing Docker (${DISTRO_ID})..."
  local SUDOCMD=""
  [ "$(id -u)" -ne 0 ] && command_exists sudo && SUDOCMD="sudo"
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
      $SUDOCMD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    fedora)
      $SUDOCMD dnf -y install dnf-plugins-core
      $SUDOCMD dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      $SUDOCMD dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      $SUDOCMD systemctl enable --now docker
      ;;
    centos|rhel|rocky|almalinux)
      $SUDOCMD yum install -y yum-utils
      $SUDOCMD yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      $SUDOCMD yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      $SUDOCMD systemctl enable --now docker
      ;;
    opensuse*|sles|suse)
      $SUDOCMD zypper install -y docker docker-compose
      $SUDOCMD systemctl enable --now docker
      ;;
    arch|manjaro|endeavouros)
      $SUDOCMD pacman -Sy --noconfirm docker docker-compose
      $SUDOCMD systemctl enable --now docker
      ;;
    alpine)
      $SUDOCMD apk add --no-cache docker docker-cli-compose
      $SUDOCMD rc-update add docker default 2>/dev/null || true
      $SUDOCMD service docker start 2>/dev/null || true
      ;;
    *)
      warn "Automatic install is not supported for '${DISTRO_ID}'. Install Docker manually, then re-run."
      return 1
      ;;
  esac
}

SUDO=""
ensure_docker() {
  detect_distro
  if ! command_exists docker; then
    warn "Docker is not installed."
    if ask_yn "Install Docker now?" y; then
      install_docker || die "Docker installation failed."
    else
      die "Docker is required."
    fi
  fi

  if docker info >/dev/null 2>&1; then
    SUDO=""
  elif [ "$(id -u)" -ne 0 ] && command_exists sudo && sudo docker info >/dev/null 2>&1; then
    SUDO="sudo "
    warn "Using sudo for the Docker daemon."
  else
    die "Cannot reach the Docker daemon. Check that it is running and that you have permission."
  fi

  if ${SUDO}docker compose version >/dev/null 2>&1; then
    DC="${SUDO}docker compose"
  elif command_exists docker-compose; then
    DC="${SUDO}docker-compose"
  else
    die "docker compose plugin or docker-compose is required."
  fi
  ok "Docker OK ($(${SUDO}docker --version 2>/dev/null | head -1)); compose='${DC# }'"
}

printf "%b\n" "${C_G}==============================================${C_0}"
printf "%b\n" "${C_G} SCLAB Vision stand-alone installer${C_0}"
printf "%b\n" "${C_G}==============================================${C_0}"
[ "$INTERACTIVE" = "0" ] && info "Unattended mode: installing with defaults."

ensure_docker

DEF_REGISTRY="873379329511.dkr.ecr.ap-northeast-2.amazonaws.com/sclabio"
GPU=0
REC_MODE="off"
VISION_REGISTRY="$DEF_REGISTRY"
VISION_TAG="0.1.1"
VISION_CONSOLE_PORT="8890"
VISION_CONTROL_PORT="8090"
VISION_GATEWAY_PORT="8080"
MONGO_ROOT_USERNAME="root"
MONGO_ROOT_PASSWORD="$(gen_secret)"
REDIS_PASSWORD="$(gen_secret)"
VISION_QDRANT_API_KEY="$(gen_secret)"
VISION_MONGO_DB="sclab_vision"
VISION_STUDIO_SHARED="false"
VISION_QDRANT_COLLECTION="VisionAnalysisVector"
VISION_RECORD_DEFAULT="off"
VISION_S3_BUCKET=""
VISION_HLS_CORS_ORIGINS="*"

echo
info "Press Enter to accept each default."

echo
printf "%b\n" "${C_B}[1/6] Accelerator${C_0}"
if ask_yn "Use an NVIDIA GPU? Requires nvidia-container-toolkit" n; then GPU=1; fi

echo
printf "%b\n" "${C_B}[2/6] Internal data services${C_0}"
echo "  Stand-alone mode starts its own MongoDB, Redis, and Qdrant containers."
MONGO_ROOT_USERNAME="$(ask "Mongo root username" "$MONGO_ROOT_USERNAME")"
MONGO_ROOT_PASSWORD="$(ask "Mongo root password" "$MONGO_ROOT_PASSWORD")"
REDIS_PASSWORD="$(ask "Redis password" "$REDIS_PASSWORD")"
VISION_MONGO_DB="$(ask "Vision Mongo DB name" "$VISION_MONGO_DB")"
VISION_QDRANT_API_KEY="$(ask "Qdrant API key" "$VISION_QDRANT_API_KEY")"
VISION_QDRANT_COLLECTION="$(ask "Qdrant collection" "$VISION_QDRANT_COLLECTION")"

echo
printf "%b\n" "${C_B}[3/6] Recording (DVR)${C_0}"
echo "  1) Disabled (default)"
echo "  2) Record to disk (./data/vision/recordings)"
echo "  3) Disk + S3 object storage (RustFS cold tier)"
rec_choice="$(ask "Choose (1/2/3)" "1")"
case "$rec_choice" in
  2) REC_MODE="disk"; VISION_RECORD_DEFAULT="always" ;;
  3) REC_MODE="s3"; VISION_RECORD_DEFAULT="always"; VISION_S3_BUCKET="sv-recordings" ;;
  *) REC_MODE="off"; VISION_RECORD_DEFAULT="off" ;;
esac

echo
printf "%b\n" "${C_B}[4/6] Exposed ports${C_0}"
VISION_CONSOLE_PORT="$(ask "Console web UI port" "$VISION_CONSOLE_PORT")"
VISION_GATEWAY_PORT="$(ask "HLS gateway port" "$VISION_GATEWAY_PORT")"
VISION_CONTROL_PORT="$(ask "Control API port" "$VISION_CONTROL_PORT")"

echo
printf "%b\n" "${C_B}[5/6] Images${C_0}"
VISION_REGISTRY="$(ask "Registry" "$VISION_REGISTRY")"
VISION_TAG="$(ask "Tag" "$VISION_TAG")"

echo
printf "%b\n" "${C_B}[6/6] Secrets${C_0}"
if ask_yn "Auto-generate Vision secrets?" y; then
  VISION_INTERNAL_TOKEN="$(gen_secret)"
  VISION_ADMIN_JWT_SECRET="$(gen_secret)"
  VISION_SIGNING_KEY="$(gen_secret)"
  ok "Generated Vision secrets"
else
  VISION_INTERNAL_TOKEN="sv-dev-internal-token"
  VISION_ADMIN_JWT_SECRET="sv-dev-admin-jwt-secret"
  VISION_SIGNING_KEY="dev-insecure-signing-key"
  warn "Using insecure development secrets."
fi

VISION_MONGO_URL="mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@mongo:27017/?authSource=admin"
VISION_REDIS_URL="redis://:${REDIS_PASSWORD}@redis:6379"
VISION_QDRANT_URL="http://qdrant:6333"

PROFILES=""
[ "$REC_MODE" = "s3" ] && PROFILES="${PROFILES:+$PROFILES,}s3"
COMPOSE_FILE_LINE=""
DC_FILES=(-f "$COMPOSE_FILE_BASE")
if [ "$GPU" = "1" ]; then
  COMPOSE_FILE_LINE="COMPOSE_FILE=docker-compose.yml:docker-compose.gpu.yml"
  DC_FILES=(-f "$COMPOSE_FILE_BASE" -f "docker-compose.gpu.yml")
fi

info "Saving configuration: .env"
{
cat <<EOF
# SCLAB Vision stand-alone, install.sh가 생성함 ($(date '+%Y-%m-%d %H:%M:%S')).
COMPOSE_PROFILES=${PROFILES}
${COMPOSE_FILE_LINE}
VISION_REGISTRY=${VISION_REGISTRY}
VISION_TAG=${VISION_TAG}
VISION_CONSOLE_PORT=${VISION_CONSOLE_PORT}
VISION_CONTROL_PORT=${VISION_CONTROL_PORT}
VISION_GATEWAY_PORT=${VISION_GATEWAY_PORT}
MONGO_ROOT_USERNAME=${MONGO_ROOT_USERNAME}
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
VISION_MONGO_URL=${VISION_MONGO_URL}
VISION_MONGO_DB=${VISION_MONGO_DB}
VISION_REDIS_URL=${VISION_REDIS_URL}
VISION_STUDIO_SHARED=${VISION_STUDIO_SHARED}
VISION_QDRANT_URL=${VISION_QDRANT_URL}
VISION_QDRANT_API_KEY=${VISION_QDRANT_API_KEY}
VISION_QDRANT_COLLECTION=${VISION_QDRANT_COLLECTION}
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

info "Creating data directories under ./data/"
mkdir -p data/mongo/db data/mongo/configdb data/redis data/qdrant data/vision/recordings data/vision/certs
[ "$REC_MODE" = "s3" ] && mkdir -p data/vision/rustfs
ok "Directories ready"

info "Checking TLS certificate"
ensure_tls_cert
ok "TLS certificate ready"

case "$VISION_REGISTRY" in
  *.dkr.ecr.*.amazonaws.com*)
    region="$(printf '%s' "$VISION_REGISTRY" | sed -n 's/.*\.dkr\.ecr\.\([a-z0-9-]*\)\.amazonaws\.com.*/\1/p')"
    host="$(printf '%s' "$VISION_REGISTRY" | sed -n 's#\(^[0-9]*\.dkr\.ecr\.[a-z0-9-]*\.amazonaws\.com\).*#\1#p')"
    if command_exists aws; then
      info "Logging in to ECR (${host})"
      if aws ecr get-login-password --region "$region" 2>/dev/null | ${SUDO}docker login --username AWS --password-stdin "$host" >/dev/null 2>&1; then
        ok "ECR login succeeded"
      else
        warn "ECR login failed. Continuing if images are already local."
      fi
    else
      warn "aws CLI not found. Skipping ECR login; pull may fail for private images."
    fi
    ;;
esac

echo
info "Pulling images"
${DC} "${DC_FILES[@]}" pull || warn "Some images failed to pull. Continuing with any local images."
info "Starting containers"
${DC} "${DC_FILES[@]}" up -d

HOSTIP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$HOSTIP" ] && HOSTIP="localhost"

echo
ok "Installation complete"
printf "%b\n" "${C_G}----------------------------------------------${C_0}"
printf "  Console web UI : ${C_B}https://%s:%s${C_0}\n" "$HOSTIP" "$VISION_CONSOLE_PORT"
printf "  Control API    : https://%s:%s\n" "$HOSTIP" "$VISION_CONTROL_PORT"
printf "  HLS gateway    : https://%s:%s\n" "$HOSTIP" "$VISION_GATEWAY_PORT"
[ "$REC_MODE" = "s3" ] && printf "  RustFS console : http://%s:9001 (rustfsadmin/rustfsadmin)\n" "$HOSTIP"
printf "%b\n" "${C_G}----------------------------------------------${C_0}"
echo "  Setup: stand-alone aio+console+mongo+redis+qdrant; $( [ "$GPU" = 1 ] && echo GPU || echo CPU ); recording=${REC_MODE}"
echo "  Status: ${DC# } ps    Logs: ./logs.sh    Stop: ./down.sh"
