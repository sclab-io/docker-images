#!/usr/bin/env bash
# make-offline-zip.sh - build an offline (air-gapped) install bundle for SCLAB Studio.
#
# Run this on a Linux machine WITH internet access. It
#   1. asks for the target OS family / CPU architecture and the services to include (checkbox menu),
#   2. installs the AWS CLI if it is missing and logs in to the private ECR registry,
#   3. downloads the Docker Engine (static binaries) and the Docker Compose plugin for the target,
#   4. pulls every selected image (docker pull) and exports it (docker save),
#   5. stores this repository (scripts, compose, env files) and the license key in the bundle,
#   6. writes ONE compressed archive split into 1 GB parts (*.part001 ...) + SHA256SUMS + MANIFEST.json
#      and copies install-offline.sh next to them.
# Upload the files of the output directory to the air-gapped server and run:  sudo ./install-offline.sh
#
# Usage: ./make-offline-zip.sh [options]      (see --help)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----------------------------------------------------------------------------- defaults
ECR_HOST="873379329511.dkr.ecr.ap-northeast-2.amazonaws.com"
ECR_REGION="ap-northeast-2"
DOCKER_VERSION_DEFAULT="28.5.2"
COMPOSE_VERSION_DEFAULT="v2.40.3"

OUT_DIR="./sclab-offline-out"
WORK_DIR=""
PART_SIZE_MB=1024
ASSUME_YES=0
TARGET_OS=""
TARGET_ARCH=""
SERVICES_ARG=""
LICENSE_FILE_ARG=""
LICENSE_KEY_ARG="${SCLAB_LICENSE_KEY:-}"
NO_LICENSE=0
NO_PULL=0
KEEP_WORK=0
BUNDLE_NAME=""
DOCKER_VERSION="$DOCKER_VERSION_DEFAULT"
COMPOSE_VERSION="$COMPOSE_VERSION_DEFAULT"

# ----------------------------------------------------------------------------- output helpers
if [ -t 1 ]; then C_G=$'\033[0;32m'; C_Y=$'\033[0;33m'; C_R=$'\033[0;31m'; C_B=$'\033[0;34m'; C_0=$'\033[0m'; else C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""; fi
info() { printf '%s\n' "${C_B}[info]${C_0} $*"; }
ok()   { printf '%s\n' "${C_G}[ ok ]${C_0} $*"; }
warn() { printf '%s\n' "${C_Y}[warn]${C_0} $*" >&2; }
err()  { printf '%s\n' "${C_R}[error]${C_0} $*" >&2; }
die()  { err "$*"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
make-offline-zip.sh - build an offline (air-gapped) install bundle for SCLAB Studio

Usage: ./make-offline-zip.sh [options]

Without options the script is interactive (menus for OS/architecture and services).

Options:
  -y, --yes                 Non-interactive: use defaults for everything not given as an option.
  --os NAME                 Target OS family: ubuntu | rhel | amzn | suse | alpine | generic
                              ubuntu = Ubuntu/Debian, rhel = RHEL/Rocky/Alma/CentOS/Oracle/Fedora,
                              amzn = Amazon Linux, suse = SUSE/openSUSE, alpine = Alpine, generic = other.
  --arch ARCH               Target architecture: x86_64 | aarch64   (default: this machine)
  --services LIST           Comma separated OPTIONAL services to include (required ones are always included).
                              "none" = only the required ones. See --list-services.
  --list-services           Print the service catalog and exit.
  --out DIR                 Output directory (default: ./sclab-offline-out)
  --name NAME               Bundle name (default: sclab-offline-<date>-<arch>)
  --part-size MB            Size of each archive part in MB (default: 1024)
  --license-file FILE       File that contains the SCLAB license key (stored in the bundle)
  --license-key KEY         License key as text (or env SCLAB_LICENSE_KEY; visible in the process list - prefer a file)
  --no-license              Do not store a license (install-offline.sh will ask for it on the server)
  --no-pull                 Do not pull: use images that already exist locally (skips AWS CLI / ECR login)
  --docker-version VER      Docker Engine static binary version (default: 28.5.2)
  --compose-version VER     Docker Compose plugin version (default: v2.40.3)
  --work-dir DIR            Staging directory (default: <out>/.work). Needs roughly the size of all images.
  --keep-work               Do not delete the staging directory at the end.
  -h, --help                Show this help.

AWS credentials for the private ECR registry come from the usual places (aws configure, AWS_PROFILE,
AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY). If none are found and the run is interactive, 'aws configure' is started.
EOF
}

# ----------------------------------------------------------------------------- service catalog
SVC_REQUIRED="mongo redis webapp sclab-proxy mail"
SVC_OPTIONAL="qdrant ai-service node-vm-service sclab-agent gis-process mqtt-client mqtt-broker kafka-client tileserver gotenberg vision vision-gpu ollama vllm speaches"

svc_desc() {
  case "$1" in
    mongo)           echo "MongoDB database" ;;
    redis)           echo "Redis cache / oplog" ;;
    webapp)          echo "SCLAB Studio web application" ;;
    sclab-proxy)     echo "nginx reverse proxy (TLS)" ;;
    mail)            echo "SMTP relay for outgoing mail" ;;
    qdrant)          echo "Qdrant vector DB (used by ai-service)" ;;
    ai-service)      echo "AI service (LLM / vector search)" ;;
    node-vm-service) echo "Node.js sandbox for scripts" ;;
    sclab-agent)     echo "DB agent (connects to external databases)" ;;
    gis-process)     echo "GIS data processing" ;;
    mqtt-client)     echo "MQTT client" ;;
    mqtt-broker)     echo "Built-in MQTT broker" ;;
    kafka-client)    echo "Kafka client" ;;
    tileserver)      echo "Map tile server (HUGE: ~95 GB image)" ;;
    gotenberg)       echo "HTML to PDF service (Gotenberg + Chromium, ~1.7 GB)" ;;
    vision)          echo "SCLAB Vision (aio + console + rustfs + nginx; ./vision)" ;;
    vision-gpu)      echo "SCLAB Vision GPU image (needs NVIDIA runtime on the server; implies vision)" ;;
    ollama)          echo "Ollama LLM runtime (models are NOT included)" ;;
    vllm)            echo "vLLM server (needs internet at start, models NOT included - see README)" ;;
    speaches)        echo "Speaches speech-to-text/TTS, CPU (models are NOT included)" ;;
  esac
}
svc_default_on() { case "$1" in qdrant|ai-service|node-vm-service|sclab-agent) return 0 ;; *) return 1 ;; esac; }

# Images of one service. Compose-default services read the staged docker-compose.yml, add-ons read their own compose file.
# $1 = service, $2 = repo directory
compose_service_image() { # $1 file, $2 service
  awk -v svc="$2" '
    $0 ~ "^  " svc ":[ \t]*$" { in_s = 1; next }
    in_s && /^  [A-Za-z0-9_-]+:/ { in_s = 0 }
    in_s && /^    image:/ { sub(/^    image:[ \t]*/, ""); gsub(/["\047]/, ""); print; exit }
  ' "$1"
}
file_images() { # every image: line of a compose file, ${VAR:-default} resolved to default
  sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "$1" | tr -d "\"'" | sed 's/[[:space:]]*#.*$//' \
    | sed 's/\${[A-Za-z_][A-Za-z0-9_]*:-\([^}]*\)}/\1/g'
}
svc_images() {
  local repo="$2"
  case "$1" in
    mongo|redis|webapp|sclab-proxy|mail|qdrant|ai-service|node-vm-service|sclab-agent|gis-process|mqtt-client|mqtt-broker|kafka-client)
      compose_service_image "$repo/docker-compose.yml" "$1" ;;
    tileserver)  file_images "$repo/tileserver/docker-compose.tileserver.yml" ;;
    gotenberg)   file_images "$repo/gotenberg/docker-compose.gotenberg.yml" ;;
    vision)      file_images "$repo/vision/docker-compose.yml" ;;
    vision-gpu)  file_images "$repo/vision/docker-compose.gpu.yml" ;;
    ollama)      file_images "$repo/ollama/docker-compose.yml" ;;
    vllm)        file_images "$repo/vllm/docker-compose.yml" ;;
    speaches)    file_images "$repo/speaches/compose.cpu.yaml" ;;
  esac
}

# ----------------------------------------------------------------------------- argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --os) TARGET_OS="${2:-}"; shift ;;
    --arch) TARGET_ARCH="${2:-}"; shift ;;
    --services) SERVICES_ARG="${2:-}"; shift ;;
    --list-services)
      echo "Required (always included):"
      for s in $SVC_REQUIRED; do printf '  %-16s %s\n' "$s" "$(svc_desc "$s")"; done
      echo "Optional:"
      for s in $SVC_OPTIONAL; do printf '  %-16s %s%s\n' "$s" "$(svc_desc "$s")" "$(svc_default_on "$s" && echo '  [default]')"; done
      exit 0 ;;
    --out) OUT_DIR="${2:-}"; shift ;;
    --name) BUNDLE_NAME="${2:-}"; shift ;;
    --part-size) PART_SIZE_MB="${2:-}"; shift ;;
    --license-file) LICENSE_FILE_ARG="${2:-}"; shift ;;
    --license-key) LICENSE_KEY_ARG="${2:-}"; shift ;;
    --no-license) NO_LICENSE=1 ;;
    --no-pull) NO_PULL=1 ;;
    --docker-version) DOCKER_VERSION="${2:-}"; shift ;;
    --compose-version) COMPOSE_VERSION="${2:-}"; shift ;;
    --work-dir) WORK_DIR="${2:-}"; shift ;;
    --keep-work) KEEP_WORK=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

case "$PART_SIZE_MB" in ''|*[!0-9]*) die "--part-size must be a number of MB." ;; esac
[ "$PART_SIZE_MB" -ge 1 ] || die "--part-size must be at least 1."

# Interactive only when stdin is a terminal and --yes was not given.
INTERACTIVE=1
if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then INTERACTIVE=0; fi

# ----------------------------------------------------------------------------- preflight
[ "$(uname -s)" = "Linux" ] || die "This script must run on Linux (detected: $(uname -s))."

for c in tar gzip split awk sed grep df find; do
  command_exists "$c" || die "Required command not found: $c"
done
if command_exists sha256sum; then SHA256="sha256sum"
elif command_exists shasum; then SHA256="shasum -a 256"
else die "sha256sum (or shasum) is required."; fi
command_exists curl || command_exists wget || die "curl or wget is required to download Docker / AWS CLI."

HOST_ARCH_RAW="$(uname -m)"
case "$HOST_ARCH_RAW" in
  x86_64|amd64) HOST_ARCH="x86_64" ;;
  aarch64|arm64) HOST_ARCH="aarch64" ;;
  *) HOST_ARCH="$HOST_ARCH_RAW" ;;
esac

SUDO=""
if [ "$(id -u)" -ne 0 ]; then command_exists sudo && SUDO="sudo"; fi

download() { # $1 url, $2 output
  if command_exists curl; then curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"
  else wget -q --tries=3 -O "$2" "$1"; fi
}

# Host package manager (used only to install missing helper tools such as unzip / docker / awscli).
pkg_install() {
  local run="$SUDO"
  if command_exists apt-get; then $run apt-get update -y >/dev/null 2>&1 || true; $run apt-get install -y "$@"
  elif command_exists dnf; then $run dnf install -y "$@"
  elif command_exists yum; then $run yum install -y "$@"
  elif command_exists zypper; then $run zypper --non-interactive install "$@"
  elif command_exists apk; then $run apk add --no-cache "$@"
  elif command_exists pacman; then $run pacman -Sy --noconfirm "$@"
  else return 1; fi
}

# ----------------------------------------------------------------------------- prompts
ask_choice() { # $1 title, $2 default index, rest "label" ... -> echoes the chosen index (1-based)
  local title="$1" def="$2" n=0 a i
  shift 2
  printf '\n%s\n' "$title" >&2
  for l in "$@"; do n=$((n + 1)); printf '  %d) %s\n' "$n" "$l" >&2; done
  while true; do
    printf 'Select [1-%d, Enter = %s]: ' "$n" "$def" >&2
    IFS= read -r a || a=""
    a="${a:-$def}"
    case "$a" in ''|*[!0-9]*) ;; *) i=$((a + 0)); if [ "$i" -ge 1 ] && [ "$i" -le "$n" ]; then echo "$i"; return 0; fi ;; esac
    echo "Invalid choice." >&2
  done
}

# ----------------------------------------------------------------------------- target OS / arch
if [ -z "$TARGET_OS" ]; then
  if [ "$INTERACTIVE" = "1" ]; then
    idx="$(ask_choice "Target server OS family (the offline server where SCLAB will be installed):" 1 \
      "Ubuntu / Debian (and derivatives)" \
      "RHEL / Rocky / AlmaLinux / CentOS / Oracle Linux / Fedora" \
      "Amazon Linux 2 / 2023" \
      "SUSE / openSUSE" \
      "Alpine Linux" \
      "Other Linux (generic)")"
    case "$idx" in 1) TARGET_OS=ubuntu ;; 2) TARGET_OS=rhel ;; 3) TARGET_OS=amzn ;; 4) TARGET_OS=suse ;; 5) TARGET_OS=alpine ;; *) TARGET_OS=generic ;; esac
  else
    TARGET_OS=generic
  fi
fi
case "$TARGET_OS" in ubuntu|rhel|amzn|suse|alpine|generic) ;; *) die "Unknown --os '$TARGET_OS' (ubuntu|rhel|amzn|suse|alpine|generic)." ;; esac

if [ -z "$TARGET_ARCH" ]; then
  if [ "$INTERACTIVE" = "1" ]; then
    def=1; [ "$HOST_ARCH" = "aarch64" ] && def=2
    idx="$(ask_choice "Target CPU architecture:" "$def" "x86_64 (amd64)" "aarch64 (arm64)")"
    case "$idx" in 1) TARGET_ARCH=x86_64 ;; *) TARGET_ARCH=aarch64 ;; esac
  else
    TARGET_ARCH="$HOST_ARCH"
  fi
fi
case "$TARGET_ARCH" in
  x86_64|amd64) TARGET_ARCH=x86_64; PLATFORM="linux/amd64" ;;
  aarch64|arm64) TARGET_ARCH=aarch64; PLATFORM="linux/arm64" ;;
  *) die "Unsupported --arch '$TARGET_ARCH' (x86_64|aarch64)." ;;
esac
info "Target: OS family=$TARGET_OS, architecture=$TARGET_ARCH ($PLATFORM)"

# ----------------------------------------------------------------------------- service selection (checkbox menu)
SELECTED=""   # space separated optional services
is_selected() { case " $SELECTED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
toggle() { if is_selected "$1"; then SELECTED="$(echo " $SELECTED " | sed "s/ $1 / /" | xargs)"; else SELECTED="$SELECTED $1"; fi; SELECTED="${SELECTED# }"; }

if [ -n "$SERVICES_ARG" ]; then
  if [ "$SERVICES_ARG" != "none" ]; then
    for s in $(echo "$SERVICES_ARG" | tr ',' ' '); do
      case " $SVC_OPTIONAL " in *" $s "*) toggle "$s" ;; *)
        case " $SVC_REQUIRED " in *" $s "*) ;; *) die "Unknown service '$s'. Use --list-services." ;; esac ;;
      esac
    done
  fi
else
  for s in $SVC_OPTIONAL; do svc_default_on "$s" && SELECTED="$SELECTED $s"; done
  SELECTED="${SELECTED# }"
  if [ "$INTERACTIVE" = "1" ]; then
    while true; do
      printf '\nServices to include in the bundle\n'
      printf '  Required (always included): %s\n' "$SVC_REQUIRED"
      printf '  Optional (type a number to toggle):\n'
      n=0
      for s in $SVC_OPTIONAL; do
        n=$((n + 1))
        if is_selected "$s"; then box="[x]"; else box="[ ]"; fi
        printf '   %2d) %s %-16s %s\n' "$n" "$box" "$s" "$(svc_desc "$s")"
      done
      printf '  a = select all, n = select none, Enter = continue: '
      IFS= read -r a || a=""
      case "$a" in
        "") break ;;
        a|A) SELECTED=""; for s in $SVC_OPTIONAL; do SELECTED="$SELECTED $s"; done; SELECTED="${SELECTED# }" ;;
        n|N) SELECTED="" ;;
        *)
          for tok in $(echo "$a" | tr ',' ' '); do
            case "$tok" in
              ''|*[!0-9]*) echo "Ignoring '$tok'." ;;
              *) k=0; found=""
                 for s in $SVC_OPTIONAL; do k=$((k + 1)); [ "$k" = "$tok" ] && found="$s"; done
                 if [ -n "$found" ]; then toggle "$found"; else echo "No such number: $tok"; fi ;;
            esac
          done ;;
      esac
    done
  fi
fi
# vision-gpu needs the vision stack
if is_selected vision-gpu && ! is_selected vision; then SELECTED="$SELECTED vision"; SELECTED="${SELECTED# }"; fi
if is_selected ai-service && ! is_selected qdrant; then warn "ai-service is selected without qdrant: it will need an external Qdrant."; fi

ALL_SERVICES="$SVC_REQUIRED $SELECTED"
ALL_SERVICES="$(echo "$ALL_SERVICES" | xargs)"
info "Services in the bundle: $ALL_SERVICES"
is_selected tileserver && warn "tileserver is selected: the bundle will be ~95 GB or more. Make sure you have roughly 2.5x that in free disk space."
is_selected vllm && warn "vllm: its compose file runs apt-get/pip at start-up (needs internet) and models are not included. Not usable on an air-gapped server as-is."

# ----------------------------------------------------------------------------- license
LICENSE_KEY=""
if [ "$NO_LICENSE" = "0" ]; then
  if [ -n "$LICENSE_FILE_ARG" ]; then
    [ -r "$LICENSE_FILE_ARG" ] || die "Cannot read license file: $LICENSE_FILE_ARG"
    LICENSE_KEY="$(grep -v '^[[:space:]]*#' "$LICENSE_FILE_ARG" | tr -d '\r' | sed -e '/^[[:space:]]*$/d' | head -1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  elif [ -n "$LICENSE_KEY_ARG" ]; then
    LICENSE_KEY="$LICENSE_KEY_ARG"
  elif [ "$INTERACTIVE" = "1" ]; then
    printf '\nSCLAB license key (stored in the bundle so the air-gapped server needs no copy/paste).\n'
    printf 'Input is hidden. Press Enter to skip (install-offline.sh will ask on the server).\n'
    printf 'License key: '
    IFS= read -r -s LICENSE_KEY || LICENSE_KEY=""
    echo
  fi
  LICENSE_KEY="$(printf '%s' "$LICENSE_KEY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$LICENSE_KEY" ]; then
    if [ "$INTERACTIVE" = "1" ]; then warn "No license key given: it will be asked during the offline installation."
    else die "No license key. Give --license-file / --license-key (or SCLAB_LICENSE_KEY), or pass --no-license."; fi
  fi
fi

# ----------------------------------------------------------------------------- output / work directories
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
[ -n "$WORK_DIR" ] || WORK_DIR="$OUT_DIR/.work"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
STAGE="$WORK_DIR/stage"
[ -n "$BUNDLE_NAME" ] || BUNDLE_NAME="sclab-offline-$(date +%Y%m%d)-${TARGET_ARCH}"
case "$BUNDLE_NAME" in *[!A-Za-z0-9._-]*) die "--name may only contain letters, digits, '.', '_' and '-'." ;; esac
if ls "$OUT_DIR/$BUNDLE_NAME".part* >/dev/null 2>&1; then
  die "$OUT_DIR already contains parts of '$BUNDLE_NAME'. Remove them or pass another --name / --out."
fi
rm -rf "$STAGE"
mkdir -p "$STAGE"/{repo,images,docker,license}

cleanup() {
  if [ "$KEEP_WORK" = "0" ] && [ -n "${STAGE:-}" ] && [ -d "${WORK_DIR:-}" ]; then rm -rf "$WORK_DIR"; rmdir "$OUT_DIR" 2>/dev/null || true; fi
}

# ----------------------------------------------------------------------------- stage the repository
info "Staging the repository files"
(
  cd "$SCRIPT_DIR"
  # Exclude VCS data, runtime state and secrets of a running installation, and the output/work directories.
  tar -cf - --exclude='./.git' --exclude='./data' --exclude='./cert' --exclude='./jwt' --exclude='./.init' \
    --exclude='./.offline' --exclude='*.bak' --exclude='./vision/data' --exclude='./vision/.env' \
    --exclude='./sclab-offline-out' --exclude='./node_modules' . 2>/dev/null
) | (cd "$STAGE/repo" && tar -xf -)
REPO="$STAGE/repo"
GIT_REV="unknown"
if command_exists git && git -C "$SCRIPT_DIR" rev-parse --short HEAD >/dev/null 2>&1; then GIT_REV="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"; fi
chmod +x "$REPO"/*.sh "$REPO"/*/*.sh 2>/dev/null || true

# Services that are in the default docker-compose.yml but were not selected: remove them from the bundled compose file.
COMPOSE_DEFAULT_SVCS="qdrant ai-service node-vm-service sclab-agent gis-process mqtt-client mqtt-broker kafka-client"
DROP=""
for s in $COMPOSE_DEFAULT_SVCS; do is_selected "$s" || DROP="$DROP $s"; done
if [ -n "$DROP" ]; then
  info "Removing unselected services from the bundled docker-compose.yml:$DROP"
  # shellcheck disable=SC2086
  (cd "$REPO" && SERVICE_MANAGE_QUIET=1 ./service-manage.sh disable $DROP >/dev/null) || die "service-manage.sh failed while trimming docker-compose.yml"
fi

# Resolve the image list now (after trimming), so only needed images are pulled.
IMAGE_LIST="$WORK_DIR/images.list"   # "service<TAB>ref"
: > "$IMAGE_LIST"
for s in $ALL_SERVICES; do
  svc_images "$s" "$REPO" | while IFS= read -r ref; do
    [ -n "$ref" ] && printf '%s\t%s\n' "$s" "$ref"
  done >> "$IMAGE_LIST"
done
[ -s "$IMAGE_LIST" ] || die "No images found for the selected services."
UNIQ_REFS="$(cut -f2 "$IMAGE_LIST" | sort -u)"

# Never pull from the registry on the offline server: make compose use the loaded images.
info "Setting pull_policy: never in the bundled compose files"
for f in "$REPO"/docker-compose.yml "$REPO"/gen.yml "$REPO"/optional-services/*.yml "$REPO"/gotenberg/*.yml \
         "$REPO"/tileserver/*.yml "$REPO"/vision/docker-compose*.yml "$REPO"/ollama/*.yml \
         "$REPO"/speaches/*.yaml "$REPO"/vllm/*.yml; do
  [ -f "$f" ] || continue
  tmp="$f.tmp"
  awk '
    { print }
    match($0, /^ +image:[ \t]/) {
      ind = substr($0, 1, RLENGTH - 7)   # leading spaces of the image: key
      sub(/[^ ].*$/, "", ind)
      print ind "pull_policy: never"
    }
  ' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
done

# ----------------------------------------------------------------------------- docker on the build machine
dk() { if [ -n "${DOCKER_SUDO:-}" ]; then $DOCKER_SUDO docker "$@"; else docker "$@"; fi; }
DOCKER_SUDO=""
ensure_build_docker() {
  if ! command_exists docker; then
    warn "Docker is not installed on this (build) machine; it is needed for docker pull / docker save."
    if [ "$INTERACTIVE" = "1" ]; then
      printf 'Try to install it with the OS package manager now? [Y/n]: '
      IFS= read -r a || a=""
    else a="y"; fi
    case "${a:-Y}" in
      [Yy]*|"")
        if command_exists apt-get; then pkg_install docker.io || true
        elif command_exists dnf || command_exists yum; then pkg_install docker || pkg_install moby-engine || true
        elif command_exists zypper || command_exists apk; then pkg_install docker || true
        else pkg_install docker || true; fi ;;
    esac
    command_exists docker || die "Docker is required. Install it (https://docs.docker.com/engine/install/) and run this script again."
  fi
  if ! docker info >/dev/null 2>&1; then
    if [ -n "$SUDO" ] && $SUDO docker info >/dev/null 2>&1; then DOCKER_SUDO="$SUDO"; warn "Using sudo for docker."
    else
      # try to start the daemon
      if command_exists systemctl; then $SUDO systemctl start docker >/dev/null 2>&1 || true; fi
      if docker info >/dev/null 2>&1; then :
      elif [ -n "$SUDO" ] && $SUDO docker info >/dev/null 2>&1; then DOCKER_SUDO="$SUDO"
      else die "Cannot reach the Docker daemon. Start it and check your permissions (docker group / sudo)."; fi
    fi
  fi
  ok "Docker: $(dk --version)"
}

# ----------------------------------------------------------------------------- AWS CLI (only needed to pull ECR images)
install_aws_cli() {
  info "Installing the AWS CLI for $HOST_ARCH ..."
  local libc_musl=0 tmp url bindir
  if [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ] || { command_exists ldd && ldd --version 2>&1 | grep -qi musl; }; then libc_musl=1; fi

  # musl (Alpine): the official AWS CLI v2 zip is built for glibc; use the distro package.
  if [ "$libc_musl" = "1" ] && command_exists apk; then
    pkg_install aws-cli && command_exists aws && return 0
  fi

  case "$HOST_ARCH" in
    x86_64) url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *) url="" ;;
  esac

  if [ -n "$url" ] && [ "$libc_musl" = "0" ]; then
    command_exists unzip || pkg_install unzip || warn "Could not install unzip."
    if command_exists unzip; then
      tmp="$(mktemp -d)"
      if download "$url" "$tmp/awscliv2.zip" && unzip -q "$tmp/awscliv2.zip" -d "$tmp"; then
        if [ "$(id -u)" -eq 0 ] || [ -n "$SUDO" ]; then
          $SUDO "$tmp/aws/install" --update -i /usr/local/aws-cli -b /usr/local/bin && { rm -rf "$tmp"; command_exists aws && return 0; }
        else
          bindir="$HOME/.local/bin"; mkdir -p "$bindir"
          "$tmp/aws/install" --update -i "$HOME/.local/aws-cli" -b "$bindir" && { rm -rf "$tmp"; export PATH="$bindir:$PATH"; command_exists aws && return 0; }
        fi
      fi
      rm -rf "$tmp"
    fi
  fi

  warn "Official installer did not work; trying the OS package manager / pip."
  if command_exists apt-get; then pkg_install awscli || true
  elif command_exists dnf || command_exists yum; then pkg_install awscli2 || pkg_install awscli || true
  elif command_exists zypper; then pkg_install aws-cli || pkg_install python3-awscli || true
  elif command_exists apk; then pkg_install aws-cli || true; fi
  if ! command_exists aws && command_exists pip3; then
    pip3 install --user awscli >/dev/null 2>&1 && export PATH="$HOME/.local/bin:$PATH" || true
  fi
  command_exists aws
}

ecr_login() {
  if ! command_exists aws; then
    install_aws_cli || die "Could not install the AWS CLI. Install it manually (https://docs.aws.amazon.com/cli/) and run again, or use --no-pull."
  fi
  ok "AWS CLI: $(aws --version 2>&1 | head -1)"
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    if [ "$INTERACTIVE" = "1" ]; then
      info "No usable AWS credentials found. Starting 'aws configure' (credentials are provided by SCLAB support)."
      aws configure
    fi
    aws sts get-caller-identity >/dev/null 2>&1 \
      || die "AWS credentials are missing or invalid. Run 'aws configure' (or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) and retry."
  fi
  info "Logging in to ECR ($ECR_HOST)"
  aws ecr get-login-password --region "$ECR_REGION" | dk login --username AWS --password-stdin "$ECR_HOST" >/dev/null \
    || die "ECR login failed. Check your AWS credentials / permissions."
  ok "ECR login succeeded"
}

# ----------------------------------------------------------------------------- Docker Engine + Compose binaries for the target
# Why static binaries: the Docker static tarball (download.docker.com/linux/static) is one self-contained set of binaries
# (dockerd, containerd, runc, ...) per CPU architecture. Unlike .deb/.rpm packages it has no per-distro/per-version
# dependency chain (containerd.io, iptables, container-selinux, ...) that can break on an offline server whose package
# repositories are unreachable, and one download works on every glibc/musl distribution. install-offline.sh adds the
# service unit (systemd / OpenRC) itself.
fetch_docker_binaries() {
  local darch carch
  case "$TARGET_ARCH" in x86_64) darch="x86_64"; carch="x86_64" ;; aarch64) darch="aarch64"; carch="aarch64" ;; esac
  info "Downloading Docker Engine $DOCKER_VERSION ($darch)"
  download "https://download.docker.com/linux/static/stable/$darch/docker-$DOCKER_VERSION.tgz" "$STAGE/docker/docker-$DOCKER_VERSION.tgz" \
    || die "Failed to download Docker $DOCKER_VERSION static binaries. Check --docker-version (see https://download.docker.com/linux/static/stable/$darch/)."
  tar -tzf "$STAGE/docker/docker-$DOCKER_VERSION.tgz" docker/dockerd >/dev/null 2>&1 || die "Downloaded Docker archive is not valid."

  info "Downloading Docker Compose $COMPOSE_VERSION ($carch)"
  local base="https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-$carch"
  download "$base" "$STAGE/docker/docker-compose" || die "Failed to download Docker Compose $COMPOSE_VERSION."
  if download "$base.sha256" "$STAGE/docker/docker-compose.sha256" 2>/dev/null; then
    local want got
    want="$(awk '{print $1}' "$STAGE/docker/docker-compose.sha256" | head -1)"
    got="$($SHA256 "$STAGE/docker/docker-compose" | awk '{print $1}')"
    [ "$want" = "$got" ] || die "Docker Compose checksum mismatch (expected $want, got $got)."
    ok "Docker Compose checksum verified"
  else
    warn "Could not fetch the Compose checksum file; skipping that verification."
  fi
  rm -f "$STAGE/docker/docker-compose.sha256"
  chmod 755 "$STAGE/docker/docker-compose"
}

# ----------------------------------------------------------------------------- pull + save images
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
safe_name() { printf '%s' "$1" | sed 's#[^A-Za-z0-9._-]#_#g'; }

NEEDS_ECR=0
if [ "$NO_PULL" = "0" ] && printf '%s\n' "$UNIQ_REFS" | grep -q '\.dkr\.ecr\.'; then NEEDS_ECR=1; fi
ensure_build_docker
[ "$NEEDS_ECR" = "1" ] && ecr_login
fetch_docker_binaries

IMAGES_TSV="$STAGE/images.tsv"   # ref<TAB>image id<TAB>file<TAB>repo digest<TAB>size bytes<TAB>service(s)
: > "$IMAGES_TSV"
total="$(printf '%s\n' "$UNIQ_REFS" | wc -l | tr -d ' ')"
idx=0
TOTAL_BYTES=0
for ref in $UNIQ_REFS; do
  idx=$((idx + 1))
  if [ "$NO_PULL" = "0" ]; then
    info "[$idx/$total] docker pull --platform $PLATFORM $ref"
    ok_pull=0
    for attempt in 1 2 3; do
      if dk pull --platform "$PLATFORM" "$ref"; then ok_pull=1; break; fi
      warn "pull failed (attempt $attempt/3)"; sleep 3
    done
    [ "$ok_pull" = "1" ] || die "Could not pull $ref"
  else
    dk image inspect "$ref" >/dev/null 2>&1 || die "--no-pull: image not present locally: $ref"
    info "[$idx/$total] using local image $ref"
  fi
  img_arch="$(dk image inspect -f '{{.Architecture}}' "$ref" 2>/dev/null || echo unknown)"
  want_arch=amd64; [ "$TARGET_ARCH" = "aarch64" ] && want_arch=arm64
  [ "$img_arch" = "$want_arch" ] || warn "$ref has architecture '$img_arch' but the target is '$want_arch'."
  id="$(dk image inspect -f '{{.Id}}' "$ref")"
  digest="$(dk image inspect -f '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$ref" 2>/dev/null || true)"
  size="$(dk image inspect -f '{{.Size}}' "$ref" 2>/dev/null || echo 0)"
  TOTAL_BYTES=$((TOTAL_BYTES + size))
  fname="$(printf '%03d' "$idx")-$(safe_name "$ref").tar"
  svcs="$(awk -F'\t' -v r="$ref" '$2 == r { printf "%s%s", (n++ ? "," : ""), $1 }' "$IMAGE_LIST")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ref" "$id" "$fname" "$digest" "$size" "$svcs" >> "$IMAGES_TSV"
done

# Disk space check (before the big export): staged tars + final parts ~ 2x the image size.
need_kb=$(( (TOTAL_BYTES / 1024) * 21 / 10 ))
have_kb="$(df -Pk "$WORK_DIR" | awk 'NR==2 {print $4}')"
info "Images total about $((TOTAL_BYTES / 1024 / 1024 / 1024)) GB; free space in $WORK_DIR: $((have_kb / 1024 / 1024)) GB; needed about $((need_kb / 1024 / 1024)) GB"
[ "$have_kb" -ge "$need_kb" ] || die "Not enough free disk space in $WORK_DIR. Free some space or use --work-dir / --out on a bigger disk."
if [ "$(df -Pk "$OUT_DIR" | awk 'NR==2 {print $1}')" != "$(df -Pk "$WORK_DIR" | awk 'NR==2 {print $1}')" ]; then
  have_out_kb="$(df -Pk "$OUT_DIR" | awk 'NR==2 {print $4}')"
  [ "$have_out_kb" -ge $(( TOTAL_BYTES / 1024 * 11 / 10 )) ] || die "Not enough free disk space in $OUT_DIR for the archive parts."
fi

idx=0
while IFS="$(printf '\t')" read -r ref id fname digest size svcs; do
  idx=$((idx + 1))
  info "[$idx/$total] docker save $ref"
  dk save -o "$STAGE/images/$fname" "$ref" || die "docker save failed for $ref"
  [ -n "$SUDO" ] && [ -n "$DOCKER_SUDO" ] && $SUDO chown "$(id -u):$(id -g)" "$STAGE/images/$fname" 2>/dev/null || true
done < "$IMAGES_TSV"

# ----------------------------------------------------------------------------- license, installer, manifest
if [ -n "$LICENSE_KEY" ]; then
  ( umask 077; printf '%s\n' "$LICENSE_KEY" > "$STAGE/license/LICENSE.key" )
  chmod 600 "$STAGE/license/LICENSE.key"
  ok "License key stored in the bundle (license/LICENSE.key, mode 600)"
else
  rm -rf "$STAGE/license"
fi
cp "$SCRIPT_DIR/install-offline.sh" "$STAGE/install-offline.sh" 2>/dev/null || die "install-offline.sh not found next to this script."
chmod +x "$STAGE/install-offline.sh"

CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "BUNDLE_NAME=$BUNDLE_NAME"
  echo "CREATED_AT=$CREATED_AT"
  echo "TARGET_OS=$TARGET_OS"
  echo "TARGET_ARCH=$TARGET_ARCH"
  echo "SERVICES=\"$ALL_SERVICES\""
  echo "DOCKER_VERSION=$DOCKER_VERSION"
  echo "COMPOSE_VERSION=$COMPOSE_VERSION"
  echo "IMAGES_BYTES=$TOTAL_BYTES"
  echo "HAS_LICENSE=$([ -n "$LICENSE_KEY" ] && echo 1 || echo 0)"
} > "$STAGE/bundle.env"

write_manifest() { # $1 = output path; $2 = parts list file (may be empty)
  local out="$1" parts="$2" first=1 svc_json="" s
  for s in $ALL_SERVICES; do svc_json="$svc_json${svc_json:+, }\"$s\""; done
  {
    echo "{"
    echo "  \"bundle_name\": \"$(json_escape "$BUNDLE_NAME")\","
    echo "  \"created_at\": \"$CREATED_AT\","
    echo "  \"repo_revision\": \"$(json_escape "$GIT_REV")\","
    echo "  \"target_os\": \"$TARGET_OS\","
    echo "  \"target_arch\": \"$TARGET_ARCH\","
    echo "  \"docker_version\": \"$DOCKER_VERSION\","
    echo "  \"compose_version\": \"$COMPOSE_VERSION\","
    echo "  \"license_included\": $([ -n "$LICENSE_KEY" ] && echo true || echo false),"
    echo "  \"images_bytes\": $TOTAL_BYTES,"
    echo "  \"services\": [$svc_json],"
    echo "  \"images\": ["
    while IFS="$(printf '\t')" read -r ref id fname digest size svcs; do
      [ "$first" = "1" ] || echo ","
      first=0
      printf '    {"ref": "%s", "id": "%s", "repo_digest": "%s", "size_bytes": %s, "services": "%s", "file": "images/%s"}' \
        "$(json_escape "$ref")" "$id" "$(json_escape "$digest")" "${size:-0}" "$svcs" "$fname"
    done < "$IMAGES_TSV"
    echo ""
    echo "  ],"
    echo "  \"parts\": ["
    if [ -n "$parts" ] && [ -s "$parts" ]; then
      first=1
      while IFS= read -r p; do
        [ "$first" = "1" ] || echo ","
        first=0
        printf '    "%s"' "$p"
      done < "$parts"
      echo ""
    fi
    echo "  ]"
    echo "}"
  } > "$out"
}
write_manifest "$STAGE/MANIFEST.json" ""
cp "$STAGE/MANIFEST.json" "$STAGE/MANIFEST.inner.json"

# ----------------------------------------------------------------------------- tar | gzip | split
COMPRESS="gzip -1"
command_exists pigz && COMPRESS="pigz -1"
info "Creating the archive and splitting it into ${PART_SIZE_MB} MB parts (compressor: ${COMPRESS%% *})"
PART_BYTES=$((PART_SIZE_MB * 1024 * 1024))
PREFIX="$OUT_DIR/$BUNDLE_NAME.tar.gz.part"
( cd "$STAGE" && tar -cf - . ) | $COMPRESS | split -a 4 -b "$PART_BYTES" - "$PREFIX.tmp_"
# rename aaaa,aaab,... -> 001,002,...
n=0
PARTS_LIST="$WORK_DIR/parts.list"
: > "$PARTS_LIST"
for f in "$PREFIX".tmp_*; do
  n=$((n + 1))
  new="$(printf '%s%03d' "$PREFIX" "$n")"
  mv "$f" "$new"
  basename "$new" >> "$PARTS_LIST"
done
[ "$n" -ge 1 ] || die "Archive creation produced no parts."
ok "$n part(s) written"

write_manifest "$OUT_DIR/MANIFEST.json" "$PARTS_LIST"
cp "$STAGE/install-offline.sh" "$OUT_DIR/install-offline.sh"
chmod +x "$OUT_DIR/install-offline.sh"

info "Computing SHA256SUMS"
(
  cd "$OUT_DIR"
  # shellcheck disable=SC2046
  $SHA256 $(cat "$PARTS_LIST") MANIFEST.json install-offline.sh > SHA256SUMS
)
ok "SHA256SUMS written"

cleanup

echo
echo "================================================================"
echo " Offline bundle ready: $OUT_DIR"
echo "================================================================"
( cd "$OUT_DIR" && ls -lh | sed 's/^/  /' )
cat <<EOF

Next steps:
  1. Copy EVERY file of $OUT_DIR to the air-gapped server (same directory):
       *.part*, SHA256SUMS, MANIFEST.json, install-offline.sh
  2. On the server (as root):   sudo bash ./install-offline.sh
     (add --yes for an unattended install with defaults; --help for all options)

Target: OS family=$TARGET_OS, arch=$TARGET_ARCH | services: $ALL_SERVICES
EOF
if [ -n "$LICENSE_KEY" ]; then
  echo "NOTE: the license key is stored in plain text inside the archive. Handle the files as confidential."
fi
