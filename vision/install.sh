#!/usr/bin/env bash
# SCLAB Vision 설치 스크립트. 기본 구성은 aio + console이며 주요 Linux 배포판에서 동작한다.
#   ./install.sh          대화형 단계별 설치(각 질문에서 Enter를 누르면 기본값 적용)
#   ./install.sh -y       무인 설치(질문 없이 모든 기본값 적용)
#
# 네트워크: sclab-network(같은 레벨의 메인 스택과 공유). 볼륨: 모든 데이터는 ./data/vision/* 아래에 저장.
set -euo pipefail

cd "$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE_BASE="docker-compose.yml"

# ─────────────────────────── 출력 헬퍼 ───────────────────────────
if [ -t 1 ]; then C_G="\033[0;32m"; C_Y="\033[0;33m"; C_R="\033[0;31m"; C_B="\033[0;34m"; C_0="\033[0m"; else C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""; fi
info() { printf "%b\n" "${C_B}▶${C_0} $*"; }
ok()   { printf "%b\n" "${C_G}✓${C_0} $*"; }
warn() { printf "%b\n" "${C_Y}⚠${C_0} $*"; }
err()  { printf "%b\n" "${C_R}✗${C_0} $*" >&2; }
die()  { err "$*"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

ASSUME_YES=0
for a in "$@"; do case "$a" in -y|--yes) ASSUME_YES=1 ;; -h|--help) sed -n '2,6p' "$0"; exit 0 ;; esac; done
# TTY가 있고 -y가 없을 때만 대화형으로 동작한다. 그 외에는 기본값을 사용한다.
if [ "$ASSUME_YES" = "1" ] || { [ ! -t 0 ] && [ ! -e /dev/tty ]; }; then INTERACTIVE=0; else INTERACTIVE=1; fi

ask() {  # $1=질문 $2=기본값 -> 답변(Enter 입력 시 기본값)
  local p="$1" d="$2" a=""
  if [ "$INTERACTIVE" = "0" ]; then echo "$d"; return; fi
  if [ -n "$d" ]; then printf "  %s [%s]: " "$p" "$d" >/dev/tty; else printf "  %s: " "$p" >/dev/tty; fi
  IFS= read -r a </dev/tty || a=""
  echo "${a:-$d}"
}
ask_yn() {  # $1=질문 $2=기본값(y|n) -> 0이면 yes
  local p="$1" d="$2" a="" hint
  case "$d" in y|Y) hint="Y/n" ;; *) hint="y/N" ;; esac
  if [ "$INTERACTIVE" = "0" ]; then case "$d" in y|Y) return 0 ;; *) return 1 ;; esac; fi
  printf "  %s [%s]: " "$p" "$hint" >/dev/tty
  IFS= read -r a </dev/tty || a=""
  a="${a:-$d}"; case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
gen_secret() {  # 랜덤 48자 hex 문자열
  if command_exists openssl; then openssl rand -hex 24
  elif [ -r /dev/urandom ]; then LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 48
  else echo "sv$(date +%s)$$${RANDOM:-0}${RANDOM:-0}" | head -c 48; fi
}
strip_quotes() {
  local v="${1:-}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}
env_file_value() {  # $1=KEY $2..=env files
  local key="$1" file value
  shift
  for file in "$@"; do
    [ -f "$file" ] || continue
    value="$(awk -v key="$key" '
      $0 ~ "^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=" {
        sub("^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=", "")
        print
        exit
      }
    ' "$file")"
    [ -n "$value" ] && strip_quotes "$value" && return 0
  done
  return 1
}
compose_env_value() {  # $1=KEY $2..=compose files
  local key="$1" file value
  shift
  for file in "$@"; do
    [ -f "$file" ] || continue
    value="$(awk -v key="$key" '
      {
        line=$0
        sub("^[[:space:]]*-[[:space:]]*", "", line)
        if (line ~ "^" key "[[:space:]]*=") {
          sub("^" key "[[:space:]]*=", "", line)
          print line
          exit
        }
        line=$0
        sub("^[[:space:]]*", "", line)
        if (line ~ "^" key "[[:space:]]*:") {
          sub("^" key "[[:space:]]*:[[:space:]]*", "", line)
          print line
          exit
        }
      }
    ' "$file")"
    [ -n "$value" ] && strip_quotes "$value" && return 0
  done
  return 1
}
compose_service_field() {  # $1=service $2=field $3..=compose files
  local svc="$1" field="$2" file value
  shift 2
  for file in "$@"; do
    [ -f "$file" ] || continue
    value="$(awk -v svc="$svc" -v field="$field" '
      $0 ~ "^  " svc ":" { in_svc=1; next }
      in_svc && $0 ~ "^  [A-Za-z0-9_-]+:" { in_svc=0 }
      in_svc {
        line=$0
        sub("^[[:space:]]*", "", line)
        if (line ~ "^" field "[[:space:]]*:") {
          sub("^" field "[[:space:]]*:[[:space:]]*", "", line)
          print line
          exit
        }
      }
    ' "$file")"
    [ -n "$value" ] && strip_quotes "$value" && return 0
  done
  return 1
}
config_value() {  # $1=KEY $2=fallback
  local key="$1" fallback="$2" value=""
  value="${!key:-}"
  [ -n "$value" ] && printf '%s' "$value" && return 0
  value="$(env_file_value "$key" .env 2>/dev/null || true)"
  [ -n "$value" ] && printf '%s' "$value" && return 0
  printf '%s' "$fallback"
}
mongo_db_from_url() {
  local url="${1:-}" db=""
  db="$(printf '%s' "$url" | sed -n 's#^mongodb://[^/]*/\([^?]*\).*$#\1#p')"
  [ -n "$db" ] && [ "$db" != "/" ] && printf '%s' "$db"
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

# ─────────────────── 배포판 감지 + Docker 설치 ───────────────────
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

# ─────────────────── Docker / Compose 준비 확인 ───────────────────
SUDO=""
ensure_docker() {
  detect_distro
  if ! command_exists docker; then
    warn "Docker is not installed."
    if ask_yn "Install Docker now?" y; then install_docker || die "Docker installation failed."; else die "Docker is required."; fi
  fi
  # Docker daemon 접근 권한 확인. 필요하면 sudo로 대체한다.
  if docker info >/dev/null 2>&1; then SUDO=""
  elif [ "$(id -u)" -ne 0 ] && command_exists sudo && sudo docker info >/dev/null 2>&1; then
    SUDO="sudo "; warn "Using sudo for the Docker daemon (add your user to the 'docker' group to avoid sudo)."
  else
    die "Cannot reach the Docker daemon. Check that it is running and that you have permission (docker group / sudo)."
  fi
  # compose v2(plugin)를 우선 사용하고, 없으면 v1로 대체한다.
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
chmod_data_dirs() {
  chmod 0777 "$@" 2>/dev/null && return 0
  if [ "$(id -u)" -ne 0 ] && command_exists sudo; then
    sudo chmod 0777 "$@"
  else
    return 1
  fi
}

# ═══════════════════════════ 설치 흐름 ═══════════════════════════
printf "%b\n" "${C_G}╔══════════════════════════════════════════════╗${C_0}"
printf "%b\n" "${C_G}║        SCLAB Vision installer (aio + console)  ║${C_0}"
printf "%b\n" "${C_G}╚══════════════════════════════════════════════╝${C_0}"
[ "$INTERACTIVE" = "0" ] && info "Unattended mode — installing with defaults."

ensure_docker
ensure_network

# 기본값
DEF_REGISTRY="873379329511.dkr.ecr.ap-northeast-2.amazonaws.com/sclabio"
GPU=0; REC_MODE="off"
VISION_STUDIO_SHARED="true"
ROOT_COMPOSE="../docker-compose.yml"
ROOT_COMMON_ENV="../common.env"
ROOT_AI_ENV="../ai-service.env"
MONGO_HOST="$(compose_service_field mongo hostname "$ROOT_COMPOSE" 2>/dev/null || true)"; MONGO_HOST="${MONGO_HOST:-mongo}"
REDIS_HOST="$(compose_service_field redis hostname "$ROOT_COMPOSE" 2>/dev/null || true)"; REDIS_HOST="${REDIS_HOST:-redis}"
QDRANT_HOST="$(compose_service_field qdrant hostname "$ROOT_COMPOSE" 2>/dev/null || true)"; QDRANT_HOST="${QDRANT_HOST:-qdrant}"
MONGO_ROOT_USERNAME="$(compose_env_value MONGO_INITDB_ROOT_USERNAME "$ROOT_COMPOSE" 2>/dev/null || true)"; MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
MONGO_ROOT_PASSWORD="$(compose_env_value MONGO_INITDB_ROOT_PASSWORD "$ROOT_COMPOSE" 2>/dev/null || true)"; MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-changeThisMongoPassword}"
REDIS_PASSWORD="$(env_file_value REDIS_PASSWORD "$ROOT_AI_ENV" 2>/dev/null || true)"
[ -n "$REDIS_PASSWORD" ] || REDIS_PASSWORD="$(compose_env_value REDIS_PASSWORD "$ROOT_COMPOSE" 2>/dev/null || true)"
REDIS_PASSWORD="${REDIS_PASSWORD:-changeThisRedisPassword}"
ROOT_MONGO_URL="$(env_file_value MONGO_URL "$ROOT_COMMON_ENV" 2>/dev/null || true)"
ROOT_REDIS_URL="$(env_file_value REDIS_URL "$ROOT_AI_ENV" 2>/dev/null || true)"
ROOT_QDRANT_URL="$(env_file_value QDRANT_CLUSTER_URL "$ROOT_COMMON_ENV" 2>/dev/null || true)"
ROOT_QDRANT_API_KEY="$(env_file_value QDRANT_API_KEY "$ROOT_COMMON_ENV" 2>/dev/null || true)"
[ -n "$ROOT_QDRANT_API_KEY" ] || ROOT_QDRANT_API_KEY="$(compose_env_value QDRANT__SERVICE__API_KEY "$ROOT_COMPOSE" 2>/dev/null || true)"
case "$ROOT_REDIS_URL" in
  redis://:*) ;;
  redis://*) ROOT_REDIS_URL="$(printf '%s' "$ROOT_REDIS_URL" | sed "s#^redis://#redis://:${REDIS_PASSWORD}@#")" ;;
  *) ROOT_REDIS_URL="" ;;
esac
VISION_MONGO_URL="$(config_value VISION_MONGO_URL "${ROOT_MONGO_URL:-mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@${MONGO_HOST}:27017/?authSource=admin}")"
VISION_MONGO_DB="$(config_value VISION_MONGO_DB "$(mongo_db_from_url "$VISION_MONGO_URL")")"; VISION_MONGO_DB="${VISION_MONGO_DB:-sclab}"
VISION_REDIS_URL="$(config_value VISION_REDIS_URL "${ROOT_REDIS_URL:-redis://:${REDIS_PASSWORD}@${REDIS_HOST}:6379}")"
VISION_QDRANT_URL="$(config_value VISION_QDRANT_URL "${ROOT_QDRANT_URL:-http://${QDRANT_HOST}:6333}")"
VISION_QDRANT_API_KEY="$(config_value VISION_QDRANT_API_KEY "${ROOT_QDRANT_API_KEY:-changeThisQdrantApiKey}")"
VISION_QDRANT_COLLECTION="$(config_value VISION_QDRANT_COLLECTION "sv-VisionAnalysisVector")"
VISION_CONSOLE_PORT="8890"; VISION_CONTROL_PORT="8090"; VISION_GATEWAY_PORT="8080"
VISION_REGISTRY="$DEF_REGISTRY"; VISION_TAG="latest"
VISION_VERSION="$VISION_TAG"
VISION_S3_BUCKET=""; VISION_RECORD_DEFAULT="off"; VISION_HLS_CORS_ORIGINS="*"

echo; info "You'll be asked a few questions. ${C_Y}Press Enter to accept the default${C_0} shown in [brackets]."

# 1) 가속기
echo; printf "%b\n" "${C_B}[1/6] Accelerator${C_0}"
if ask_yn "Use an NVIDIA GPU? (default: CPU; requires nvidia-container-toolkit)" n; then GPU=1; fi

# 2) 공유 서비스
echo; printf "%b\n" "${C_B}[2/6] Shared services (MongoDB / Redis / Qdrant)${C_0}"
echo "  Vision uses the existing mongo, redis, and qdrant containers on sclab-network."
echo "  Press Enter unless you changed the passwords or service names in the main SCLAB stack."
VISION_MONGO_URL="$(ask "Mongo URL" "$VISION_MONGO_URL")"
VISION_MONGO_DB="$(ask "Mongo DB name" "$VISION_MONGO_DB")"
VISION_REDIS_URL="$(ask "Redis URL" "$VISION_REDIS_URL")"
VISION_QDRANT_URL="$(ask "Qdrant URL" "$VISION_QDRANT_URL")"
VISION_QDRANT_API_KEY="$(ask "Qdrant API key" "$VISION_QDRANT_API_KEY")"
VISION_QDRANT_COLLECTION="$(ask "Qdrant collection" "$VISION_QDRANT_COLLECTION")"

# 3) 녹화(DVR)
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

# 4) 메인 HTTPS 프록시 포트
echo; printf "%b\n" "${C_B}[4/6] Main HTTPS proxy ports${C_0}"
echo "  Vision HTTPS ports are exposed by the root sclab-proxy container."
echo "  Console=${VISION_CONSOLE_PORT}, HLS gateway=${VISION_GATEWAY_PORT}, Control API=${VISION_CONTROL_PORT}"

# 5) 이미지
echo; printf "%b\n" "${C_B}[5/6] Images${C_0}"
VISION_REGISTRY="$(ask "Registry" "$VISION_REGISTRY")"
VISION_TAG="$(ask "Tag" "$VISION_TAG")"
VISION_VERSION="$VISION_TAG"

# 6) secret
echo; printf "%b\n" "${C_B}[6/6] Secrets (production security)${C_0}"
if ask_yn "Auto-generate secrets? (no = keep insecure dev defaults)" y; then
  VISION_INTERNAL_TOKEN="$(gen_secret)"; VISION_ADMIN_JWT_SECRET="$(gen_secret)"; VISION_SIGNING_KEY="$(gen_secret)"; VISION_SECRET_KEY="$(gen_secret)"
  ok "Generated 4 random secrets"
else
  VISION_INTERNAL_TOKEN="sv-dev-internal-token"; VISION_ADMIN_JWT_SECRET="sv-dev-admin-jwt-secret"; VISION_SIGNING_KEY="dev-insecure-signing-key"; VISION_SECRET_KEY="dev-insecure-secret-key"
  warn "Using insecure dev secrets — do NOT expose in production."
fi
SESSION_SECRET="${VISION_ADMIN_JWT_SECRET}"
SESSION_MAX_AGE="2592000"

# ── profile / COMPOSE_FILE 조립 ──
PROFILES=""
[ "$REC_MODE" = "s3" ] && PROFILES="${PROFILES:+$PROFILES,}s3"
COMPOSE_FILE_LINE=""
DC_FILES=(-f "$COMPOSE_FILE_BASE")
if [ "$GPU" = "1" ]; then
  COMPOSE_FILE_LINE="COMPOSE_FILE=docker-compose.yml:docker-compose.gpu.yml"
  DC_FILES=(-f "$COMPOSE_FILE_BASE" -f "docker-compose.gpu.yml")
fi

# ── .env 작성 ──
info "Saving configuration: .env"
{
cat <<EOF
# SCLAB Vision - install.sh가 생성함 ($(date '+%Y-%m-%d %H:%M:%S')). 수정 후 ./up.sh를 실행해 적용한다.
COMPOSE_PROFILES=${PROFILES}
${COMPOSE_FILE_LINE}
VISION_REGISTRY=${VISION_REGISTRY}
VISION_TAG=${VISION_TAG}
VISION_VERSION=${VISION_VERSION}
VISION_CONSOLE_PORT=${VISION_CONSOLE_PORT}
VISION_CONTROL_PORT=${VISION_CONTROL_PORT}
VISION_GATEWAY_PORT=${VISION_GATEWAY_PORT}
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

# ── 데이터 디렉터리 ──
info "Creating data directories under ./data/vision/"
mkdir -p data/vision/app data/vision/recordings
DATA_DIRS=(data/vision/app data/vision/recordings)
if [ "$REC_MODE" = "s3" ]; then
  mkdir -p data/vision/rustfs data/vision/rustfs-logs
  DATA_DIRS+=(data/vision/rustfs data/vision/rustfs-logs)
fi
chmod_data_dirs "${DATA_DIRS[@]}"
ok "Directories ready"

# ── ECR 로그인(레지스트리가 ECR인 경우) ──
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

# ── 요약 ──
HOSTIP=""
if command_exists hostname && hostname -I >/dev/null 2>&1; then
  HOSTIP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
[ -z "$HOSTIP" ] && HOSTIP="localhost"
echo
ok "Installation complete!"
printf "%b\n" "${C_G}────────────────────────────────────────────${C_0}"
printf "  Console web UI : ${C_B}https://%s:%s${C_0}\n" "$HOSTIP" "$VISION_CONSOLE_PORT"
printf "  Control API    : https://%s:%s\n" "$HOSTIP" "$VISION_CONTROL_PORT"
printf "  HLS gateway    : https://%s:%s\n" "$HOSTIP" "$VISION_GATEWAY_PORT"
[ "$REC_MODE" = "s3" ] && printf "  RustFS console : http://%s:9001 (rustfsadmin/rustfsadmin)\n" "$HOSTIP"
printf "%b\n" "${C_G}────────────────────────────────────────────${C_0}"
if ADMIN_LOGIN_TOKEN="$(mint_admin_login_token)"; then
  printf "  Admin login token:\n"
  printf "  %s\n" "$ADMIN_LOGIN_TOKEN"
else
  warn "Could not generate the admin login token locally. Check the console logs instead."
fi
echo   "  Setup: aio+console · $( [ "$GPU" = 1 ] && echo GPU || echo CPU ) · recording=${REC_MODE}"
echo   "  Data services: shared mongo/redis/qdrant on sclab-network"
echo   "  HTTPS proxy: root sclab-proxy on ports ${VISION_CONSOLE_PORT}/${VISION_CONTROL_PORT}/${VISION_GATEWAY_PORT}"
echo   "  Status: ${DC# } ps    Logs: ./logs.sh    Stop: ./down.sh"
warn "Shared service mode: mongo, redis, and qdrant must already be running on sclab-network."
