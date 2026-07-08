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
chmod_data_dirs() {
  chmod 0777 "$@" 2>/dev/null && return 0
  if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
    sudo chmod 0777 "$@"
  else
    return 1
  fi
}

detect_architecture() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ARCH_NORMALIZED="x86_64" ;;
    aarch64|arm64) ARCH_NORMALIZED="aarch64" ;;
    *) ARCH_NORMALIZED="$ARCH" ;;
  esac
}

download_file() {
  local url="$1" output="$2"
  if command_exists curl; then
    curl -fsSL "$url" -o "$output"
  elif command_exists wget; then
    wget -q "$url" -O "$output"
  else
    die "curl or wget is required to download AWS CLI."
  fi
}

base64url_openssl() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

mint_admin_login_token() {
  local tenant="t_01J9Z3K8QP4R7M2N5V8X1Y6W0A"
  local max_age="${SESSION_MAX_AGE:-2592000}"
  if command_exists python3; then
    SESSION_SECRET="$SESSION_SECRET" ADMIN_TENANT="$tenant" SESSION_MAX_AGE="$max_age" python3 - <<'PY'
import base64
import hashlib
import hmac
import os
import time

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

now = int(time.time())
exp = now + int(os.environ["SESSION_MAX_AGE"])
header = b'{"alg":"HS256"}'
payload = (
    '{"tenant_id":"%s","sub":"admin","iat":%d,"exp":%d}'
    % (os.environ["ADMIN_TENANT"], now, exp)
).encode("utf-8")
signing_input = f"{b64url(header)}.{b64url(payload)}"
sig = hmac.new(os.environ["SESSION_SECRET"].encode("utf-8"), signing_input.encode("ascii"), hashlib.sha256).digest()
print(f"{signing_input}.{b64url(sig)}")
PY
  elif command_exists openssl; then
    local now exp header payload signing_input sig
    now="$(date +%s)"
    exp=$((now + max_age))
    header='{"alg":"HS256"}'
    payload="$(printf '{"tenant_id":"%s","sub":"admin","iat":%s,"exp":%s}' "$tenant" "$now" "$exp")"
    signing_input="$(printf '%s' "$header" | base64url_openssl).$(printf '%s' "$payload" | base64url_openssl)"
    sig="$(printf '%s' "$signing_input" | openssl dgst -sha256 -hmac "$SESSION_SECRET" -binary | base64url_openssl)"
    printf '%s.%s\n' "$signing_input" "$sig"
  else
    return 1
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

install_aws_cli() {
  detect_architecture
  info "Installing AWS CLI (${ARCH_NORMALIZED})..."
  local tmp aws_url sudocmd=""
  [ "$(id -u)" -ne 0 ] && command_exists sudo && sudocmd="sudo"

  if ! command_exists unzip; then
    case "$DISTRO_ID" in
      ubuntu|debian|raspbian|linuxmint|pop) $sudocmd apt-get update -y && $sudocmd apt-get install -y unzip ;;
      fedora) $sudocmd dnf install -y unzip ;;
      centos|rhel|rocky|almalinux) $sudocmd yum install -y unzip ;;
      opensuse*|sles|suse) $sudocmd zypper install -y unzip ;;
      arch|manjaro|endeavouros) $sudocmd pacman -Sy --noconfirm unzip ;;
      alpine) $sudocmd apk add --no-cache unzip ;;
      *) die "unzip is required to install AWS CLI. Install unzip manually, then re-run." ;;
    esac
  fi

  case "$ARCH_NORMALIZED" in
    x86_64) aws_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64) aws_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *) die "AWS CLI automatic install is not supported for architecture: ${ARCH_NORMALIZED}" ;;
  esac

  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t sclab-aws.XXXXXX)"
  download_file "$aws_url" "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  $sudocmd "$tmp/aws/install" --update -i /usr/local/aws -b /usr/local/bin
  rm -rf "$tmp"
  ok "AWS CLI installed ($(aws --version 2>/dev/null))"
}

ensure_aws_cli() {
  if command_exists aws; then
    ok "AWS CLI OK ($(aws --version 2>/dev/null))"
    return 0
  fi

  warn "AWS CLI is not installed."
  if ask_yn "Install AWS CLI now?" y; then
    install_aws_cli
  else
    die "AWS CLI is required to log in to ECR and pull private Vision images."
  fi
}

ensure_aws_credentials() {
  local creds_file="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  if [ -f "$creds_file" ] && grep -q "aws_access_key_id" "$creds_file" 2>/dev/null; then
    ok "AWS credentials found"
    return 0
  fi

  warn "AWS credentials not found."
  if [ "$INTERACTIVE" = "0" ]; then
    warn "Unattended mode: skipping aws configure. Pull may fail unless credentials are provided by environment/role."
    return 0
  fi

  if ask_yn "Configure AWS credentials now? (required for private ECR images)" y; then
    aws configure
    if [ -f "$creds_file" ] && grep -q "aws_access_key_id" "$creds_file" 2>/dev/null; then
      ok "AWS credentials configured"
    else
      warn "AWS credentials were not written to ${creds_file}. Pull may fail."
    fi
  else
    warn "Skipping AWS credential configuration. Pull may fail for private images."
  fi
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
VISION_TAG="latest"
VISION_VERSION="$VISION_TAG"
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
VISION_VERSION="$VISION_TAG"

echo
printf "%b\n" "${C_B}[6/6] Secrets${C_0}"
if ask_yn "Auto-generate Vision secrets?" y; then
  VISION_INTERNAL_TOKEN="$(gen_secret)"
  VISION_ADMIN_JWT_SECRET="$(gen_secret)"
  VISION_SIGNING_KEY="$(gen_secret)"
  VISION_SECRET_KEY="$(gen_secret)"
  ok "Generated Vision secrets"
else
  VISION_INTERNAL_TOKEN="sv-dev-internal-token"
  VISION_ADMIN_JWT_SECRET="sv-dev-admin-jwt-secret"
  VISION_SIGNING_KEY="dev-insecure-signing-key"
  VISION_SECRET_KEY="dev-insecure-secret-key"
  warn "Using insecure development secrets."
fi
SESSION_SECRET="${VISION_ADMIN_JWT_SECRET}"
SESSION_MAX_AGE="2592000"

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
VISION_VERSION=${VISION_VERSION}
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
SESSION_SECRET=${SESSION_SECRET}
SESSION_MAX_AGE=${SESSION_MAX_AGE}
VISION_SIGNING_KEY=${VISION_SIGNING_KEY}
VISION_SECRET_KEY=${VISION_SECRET_KEY}
VISION_HLS_CORS_ORIGINS=${VISION_HLS_CORS_ORIGINS}
VISION_RECORD_DEFAULT=${VISION_RECORD_DEFAULT}
VISION_RECORD_DELETE_AFTER=86400
VISION_S3_BUCKET=${VISION_S3_BUCKET}
VISION_S3_ENDPOINT=http://rustfs:9000
VISION_S3_REGION=us-east-1
VISION_S3_ACCESS_KEY_ID=rustfsadmin
VISION_S3_SECRET_ACCESS_KEY=rustfsadmin
VISION_S3_PREFIX=recordings
VISION_S3_API_PORT=19000
VISION_S3_CONSOLE_PORT=19001
RUST_LOG=info
EOF
} > .env
ok ".env written"

info "Creating data directories under ./data/"
mkdir -p data/mongo/db data/mongo/configdb data/redis data/qdrant data/vision/app data/vision/recordings data/vision/certs
DATA_DIRS=(data/vision/app data/vision/recordings)
if [ "$REC_MODE" = "s3" ]; then
  mkdir -p data/vision/rustfs data/vision/rustfs-logs
  DATA_DIRS+=(data/vision/rustfs data/vision/rustfs-logs)
fi
chmod_data_dirs "${DATA_DIRS[@]}"
ok "Directories ready"

info "Checking TLS certificate"
ensure_tls_cert
ok "TLS certificate ready"

case "$VISION_REGISTRY" in
  *.dkr.ecr.*.amazonaws.com*)
    region="$(printf '%s' "$VISION_REGISTRY" | sed -n 's/.*\.dkr\.ecr\.\([a-z0-9-]*\)\.amazonaws\.com.*/\1/p')"
    host="$(printf '%s' "$VISION_REGISTRY" | sed -n 's#\(^[0-9]*\.dkr\.ecr\.[a-z0-9-]*\.amazonaws\.com\).*#\1#p')"
    ensure_aws_cli
    ensure_aws_credentials
    info "Logging in to ECR (${host})"
    if aws ecr get-login-password --region "$region" 2>/dev/null | ${SUDO}docker login --username AWS --password-stdin "$host" >/dev/null 2>&1; then
      ok "ECR login succeeded"
    else
      warn "ECR login failed. Continuing if images are already local."
    fi
    ;;
esac

echo
info "Pulling images"
${DC} "${DC_FILES[@]}" pull || warn "Some images failed to pull. Continuing with any local images."
info "Starting containers"
${DC} "${DC_FILES[@]}" up -d

HOSTIP=""
if command_exists hostname && hostname -I >/dev/null 2>&1; then
  HOSTIP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
[ -z "$HOSTIP" ] && HOSTIP="localhost"

echo
ok "Installation complete"
printf "%b\n" "${C_G}----------------------------------------------${C_0}"
printf "  Console web UI : ${C_B}https://%s:%s${C_0}\n" "$HOSTIP" "$VISION_CONSOLE_PORT"
printf "  Control API    : https://%s:%s\n" "$HOSTIP" "$VISION_CONTROL_PORT"
printf "  HLS gateway    : https://%s:%s\n" "$HOSTIP" "$VISION_GATEWAY_PORT"
[ "$REC_MODE" = "s3" ] && printf "  RustFS console : http://%s:9001 (rustfsadmin/rustfsadmin)\n" "$HOSTIP"
printf "%b\n" "${C_G}----------------------------------------------${C_0}"
if ADMIN_LOGIN_TOKEN="$(mint_admin_login_token)"; then
  printf "  Admin login token:\n"
  printf "  %s\n" "$ADMIN_LOGIN_TOKEN"
else
  warn "Could not generate the admin login token locally. Check the console logs instead."
fi
echo "  Setup: stand-alone aio+console+mongo+redis+qdrant; $( [ "$GPU" = 1 ] && echo GPU || echo CPU ); recording=${REC_MODE}"
echo "  Status: ${DC# } ps    Logs: ./logs.sh    Stop: ./down.sh"
