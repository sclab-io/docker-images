#!/usr/bin/env bash
# make-offline-update-zip.sh - build an UPDATE bundle (selected images only) for an already installed offline SCLAB Studio.
#
# Run this on a Linux or macOS (Intel / Apple Silicon) machine WITH internet access. It
#   1. asks which services / images to update (checkbox menu; --services for unattended use),
#   2. installs the AWS CLI if it is missing and logs in to the private ECR registry,
#   3. pulls the selected images (docker pull --platform linux/amd64) and exports them (docker save),
#   4. optionally (--with-compose) snapshots the compose / script / config files of this repository,
#   5. writes ONE compressed archive split into 1 GB parts + <name>.SHA256SUMS + <name>.MANIFEST.json.
# Every output file starts with the bundle name, so several update bundles can live in the same directory
# (also on the server). Copy them to the air-gapped server and run:  sudo ./update-offline-images.sh
#
# No license key is stored: an update does not need one. Use make-offline-zip.sh for a full (first-time) install bundle.
# Usage: ./make-offline-update-zip.sh [options]      (see --help)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----------------------------------------------------------------------------- defaults
ECR_HOST="873379329511.dkr.ecr.ap-northeast-2.amazonaws.com"
ECR_REGION="ap-northeast-2"

OUT_DIR="./sclab-update-out"
WORK_DIR=""
PART_SIZE_MB=1024
ASSUME_YES=0
TARGET_ARCH=""
SERVICES_ARG=""
NO_PULL=0
KEEP_WORK=0
WITH_COMPOSE=0
BUNDLE_NAME=""
BASE_BUNDLE_ARG=""
BASE_MANIFEST_ARG=""

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
make-offline-update-zip.sh - build an update bundle (only the images you pick) for an installed offline SCLAB Studio
(runs on Linux or macOS; the bundle is applied on the LINUX server with update-offline-images.sh)

Usage: ./make-offline-update-zip.sh [options]

Without options the script is interactive (arrow-key checkbox menu: Up/Down or j/k move, Space toggles,
Enter confirms; a numeric prompt is used when there is no terminal).

Options:
  -y, --yes                 Non-interactive: use defaults for everything not given as an option.
  --services LIST           Comma separated services to update, e.g. webapp,ai-service (default: webapp).
                              See --list-services.
  --list-services           Print the service catalog and exit.
  --arch ARCH               Target architecture: x86_64 (default). aarch64/arm64 is not supported yet.
  --out DIR                 Output directory (default: ./sclab-update-out). Files are prefixed with the bundle name,
                              so you can build several update bundles into the same directory.
  --name NAME               Bundle name (default: sclab-update-<YYYYMMDD-HHMMSS>-<arch>)
  --part-size MB            Size of each archive part in MB (default: 1024)
  --with-compose            Also store a snapshot of this repository's compose / script / config files. The server
                              merges them into the installed copy and shows the diff first (env files, settings.json,
                              certificates and data are never overwritten). Default: images only.
  --base-bundle NAME        Name of the full bundle this update is meant for (recorded in MANIFEST.json).
  --base-manifest FILE      MANIFEST.json of that full bundle (bundle name and repo revision are recorded).
  --no-pull                 Do not pull: use images that already exist locally (skips AWS CLI / ECR login)
  --work-dir DIR            Staging directory (default: <out>/.work-<name>). Needs about the size of the images.
  --keep-work               Do not delete the staging directory at the end.
  -h, --help                Show this help.

AWS credentials for the private ECR registry come from the usual places (aws configure, AWS_PROFILE,
AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY). If none are found and the run is interactive, 'aws configure' is started.
EOF
}

# ----------------------------------------------------------------------------- service catalog (same services as make-offline-zip.sh)
SVC_REQUIRED="mongo redis webapp sclab-proxy mail"
SVC_OPTIONAL="qdrant ai-service node-vm-service sclab-agent gis-process mqtt-client mqtt-broker kafka-client tileserver gotenberg vision vision-gpu ollama vllm speaches"
SVC_ALL="$SVC_REQUIRED $SVC_OPTIONAL"

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
    vision)          echo "SCLAB Vision (aio + console + rustfs + nginx)" ;;
    vision-gpu)      echo "SCLAB Vision GPU image" ;;
    ollama)          echo "Ollama LLM runtime" ;;
    vllm)            echo "vLLM server" ;;
    speaches)        echo "Speaches speech-to-text/TTS, CPU" ;;
  esac
}

compose_service_image() { # $1 file, $2 service
  awk -v svc="$2" '
    $0 ~ "^  " svc ":[ \t]*$" { in_s = 1; next }
    in_s && /^  [A-Za-z0-9_-]+:/ { in_s = 0 }
    in_s && /^    image:/ { sub(/^    image:[ \t]*/, ""); gsub(/["\047]/, ""); print; exit }
  ' "$1" | sed 's/\${[A-Za-z_][A-Za-z0-9_]*:-\([^}]*\)}/\1/g'   # ${VAR:-default} -> default
}
file_images() { # every image: line of a compose file, ${VAR:-default} resolved to default
  sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "$1" | tr -d "\"'" | sed 's/[[:space:]]*#.*$//' \
    | sed 's/\${[A-Za-z_][A-Za-z0-9_]*:-\([^}]*\)}/\1/g'
}
svc_images() { # $1 service, $2 repo directory
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
    --services) SERVICES_ARG="${2:-}"; shift ;;
    --list-services)
      echo "Services (images that can be put into an update bundle):"
      for s in $SVC_ALL; do printf '  %-16s %s\n' "$s" "$(svc_desc "$s")"; done
      exit 0 ;;
    --arch) TARGET_ARCH="${2:-}"; shift ;;
    --out) OUT_DIR="${2:-}"; shift ;;
    --name) BUNDLE_NAME="${2:-}"; shift ;;
    --part-size) PART_SIZE_MB="${2:-}"; shift ;;
    --with-compose) WITH_COMPOSE=1 ;;
    --base-bundle) BASE_BUNDLE_ARG="${2:-}"; shift ;;
    --base-manifest) BASE_MANIFEST_ARG="${2:-}"; shift ;;
    --no-pull) NO_PULL=1 ;;
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
HOST_OS="$(uname -s)"
case "$HOST_OS" in
  Linux|Darwin) ;;
  *) die "This script runs on Linux or macOS (detected: $HOST_OS)." ;;
esac
HOST_ARCH_RAW="$(uname -m)"
case "$HOST_ARCH_RAW" in
  x86_64|amd64) HOST_ARCH="x86_64" ;;
  aarch64|arm64) HOST_ARCH="aarch64" ;;
  *) HOST_ARCH="$HOST_ARCH_RAW" ;;
esac

SUDO=""
# macOS: tools come from Homebrew (never run as root) - no sudo for package installs.
if [ "$HOST_OS" != "Darwin" ] && [ "$(id -u)" -ne 0 ]; then command_exists sudo && SUDO="sudo"; fi

download() { # $1 url, $2 output
  if command_exists curl; then curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"
  else wget -q --tries=3 -O "$2" "$1"; fi
}

pkg_install() {
  local run="$SUDO"
  if [ "$HOST_OS" = "Darwin" ]; then
    command_exists brew && brew install "$@"
    return
  fi
  if command_exists apt-get; then $run apt-get update -y >/dev/null 2>&1 || true; $run apt-get install -y "$@"
  elif command_exists dnf; then $run dnf install -y "$@"
  elif command_exists yum; then $run yum install -y "$@"
  elif command_exists zypper; then $run zypper --non-interactive install "$@"
  elif command_exists apk; then $run apk add --no-cache "$@"
  elif command_exists pacman; then $run pacman -Sy --noconfirm "$@"
  else return 1; fi
}

ensure_tools() {
  local missing="" c pk
  for c in tar gzip split awk sed grep df find; do command_exists "$c" || missing="$missing $c"; done
  command_exists curl || command_exists wget || missing="$missing curl"
  if command_exists sha256sum || command_exists shasum; then :; else missing="$missing sha256sum"; fi
  [ -z "$missing" ] && return 0
  if [ "$HOST_OS" = "Darwin" ]; then die "Required tool(s) missing on macOS:$missing (install the Xcode command line tools: xcode-select --install)."; fi
  warn "Missing tools:$missing - trying to install them with the package manager."
  pk=""
  for c in $missing; do
    case "$c" in
      split|df|sha256sum) pk="$pk coreutils" ;;
      find) pk="$pk findutils" ;;
      awk) pk="$pk gawk" ;;
      *) pk="$pk $c" ;;
    esac
  done
  # shellcheck disable=SC2086
  pk="$(printf '%s\n' $pk | sort -u | tr '\n' ' ')"
  # shellcheck disable=SC2086
  pkg_install $pk >/dev/null 2>&1 || true
  for c in $missing; do
    case "$c" in
      curl) command_exists curl || command_exists wget || die "Could not install curl. Install curl or wget and run again." ;;
      sha256sum) command_exists sha256sum || command_exists shasum || die "Could not install sha256sum." ;;
      *) command_exists "$c" || die "Required command not found and could not be installed: $c" ;;
    esac
  done
}
ensure_tools
if command_exists sha256sum; then SHA256="sha256sum"; else SHA256="shasum -a 256"; fi

# ----------------------------------------------------------------------------- menus (same keys as make-offline-zip.sh, plus scrolling)
# Arrow-key menus need a real terminal on stdin and stderr. Pipes/CI, TERM=dumb or an unset TERM use the numeric prompts.
USE_ARROWS=0
if [ "$INTERACTIVE" = "1" ] && [ -t 2 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != "dumb" ]; then USE_ARROWS=1; fi
TERM_ROWS=24; TERM_COLS=80
if [ "$USE_ARROWS" = "1" ]; then
  tsz="$(stty size 2>/dev/null)" || tsz=""
  case "$tsz" in
    [0-9]*" "[0-9]*) TERM_ROWS="${tsz% *}"; TERM_COLS="${tsz#* }" ;;
  esac
  [ "$TERM_ROWS" -gt 0 ] 2>/dev/null || TERM_ROWS=24
  [ "$TERM_COLS" -gt 20 ] 2>/dev/null || TERM_COLS=80
fi

# Reads one key (bash 3.2 compatible: no fractional read timeout; an ESC is followed by a read of the next 2 chars).
# Sets MENU_KEY to: up | down | space | enter | all | none | eof | other
MENU_KEY=""
menu_read_key() {
  local k k2=""
  IFS= read -rsn1 k || { MENU_KEY=eof; return 0; }
  case "$k" in
    "") MENU_KEY=enter ;;
    " ") MENU_KEY=space ;;
    k|K) MENU_KEY=up ;;
    j|J) MENU_KEY=down ;;
    a|A) MENU_KEY=all ;;
    n|N) MENU_KEY=none ;;
    $'\033')
      IFS= read -rsn2 k2 || k2=""
      case "$k2" in
        "[A"|"OA") MENU_KEY=up ;;
        "[B"|"OB") MENU_KEY=down ;;
        *) MENU_KEY=other ;;
      esac ;;
    *) MENU_KEY=other ;;
  esac
}

MENU_SAVED_STTY=""
menu_restore() { # always leave the terminal usable: restore stty and show the cursor
  [ -n "$MENU_SAVED_STTY" ] && stty "$MENU_SAVED_STTY" 2>/dev/null || true
  printf '\033[?25h' >&2
}

# Draws (or redraws in place) the menu with a scrolling window. Items: MI_LABEL / MI_DESC / MI_ON; MENU_CUR = cursor row (0-based).
menu_draw() { # $1 = 1 on the first draw
  local i mark plain end
  [ "$1" = "1" ] || printf '\033[%dA' "$MENU_LINES" >&2
  if [ "$MENU_CUR" -lt "$MENU_TOP" ]; then MENU_TOP="$MENU_CUR"; fi
  if [ "$MENU_CUR" -ge $((MENU_TOP + MENU_VIS)) ]; then MENU_TOP=$((MENU_CUR - MENU_VIS + 1)); fi
  printf '\r\033[K%s\n' "$MENU_TITLE" >&2
  if [ -n "$MENU_HEADER" ]; then printf '\r\033[K%s\n' "${MENU_HEADER:0:$((TERM_COLS - 1))}" >&2; fi
  i="$MENU_TOP"; end=$((MENU_TOP + MENU_VIS))
  while [ "$i" -lt "$end" ]; do
    if [ "$MENU_MODE" = "multi" ]; then
      mark="[ ]"; [ "${MI_ON[$i]}" = "1" ] && mark="[x]"
      plain="$(printf '%s %s %-16s %s' "$([ "$i" = "$MENU_CUR" ] && echo '>' || echo ' ')" "$mark" "${MI_LABEL[$i]}" "${MI_DESC[$i]}")"
    else
      plain="$(printf '%s %s' "$([ "$i" = "$MENU_CUR" ] && echo '>' || echo ' ')" "${MI_LABEL[$i]}")"
    fi
    plain="  ${plain:0:$((TERM_COLS - 3))}"
    if [ "$i" = "$MENU_CUR" ]; then printf '\r\033[K\033[7m%s\033[0m\n' "$plain" >&2; else printf '\r\033[K%s\n' "$plain" >&2; fi
    i=$((i + 1))
  done
  plain="$MENU_FOOTER"
  if [ "$MENU_N" -gt "$MENU_VIS" ]; then plain="$plain  ($((MENU_TOP + 1))-$end of $MENU_N)"; fi
  printf '\r\033[K%s\n' "${plain:0:$((TERM_COLS - 1))}" >&2
}

# $1 = multi|single, $2 = title, $3 = header line (may be empty), $4 = initial cursor row (0-based).
# multi: result is left in MI_ON; single: the chosen row is left in MENU_CUR.
arrow_menu() {
  local i
  MENU_MODE="$1"; MENU_TITLE="$2"; MENU_HEADER="$3"; MENU_CUR="$4"; MENU_N="${#MI_LABEL[@]}"; MENU_TOP=0
  MENU_VIS="$MENU_N"
  i=$((TERM_ROWS - 5)); [ -n "$MENU_HEADER" ] && i=$((i - 1))
  [ "$i" -ge 3 ] || i=3
  [ "$MENU_VIS" -le "$i" ] || MENU_VIS="$i"
  MENU_LINES=$((MENU_VIS + 2)); [ -n "$MENU_HEADER" ] && MENU_LINES=$((MENU_LINES + 1))
  if [ "$MENU_MODE" = "multi" ]; then
    MENU_FOOTER="  Up/Down (or j/k) move | Space toggle | a all | n none | Enter confirm"
  else
    MENU_FOOTER="  Up/Down (or j/k) move | Enter select"
  fi
  MENU_SAVED_STTY="$(stty -g 2>/dev/null)" || MENU_SAVED_STTY=""
  trap 'menu_restore; exit 130' INT TERM HUP
  trap 'menu_restore' EXIT
  printf '\n\033[?25l' >&2
  menu_draw 1
  while true; do
    menu_read_key
    case "$MENU_KEY" in
      up) MENU_CUR=$(( (MENU_CUR + MENU_N - 1) % MENU_N )) ;;
      down) MENU_CUR=$(( (MENU_CUR + 1) % MENU_N )) ;;
      space) if [ "$MENU_MODE" = "multi" ]; then if [ "${MI_ON[MENU_CUR]}" = "1" ]; then MI_ON[MENU_CUR]=0; else MI_ON[MENU_CUR]=1; fi; fi ;;
      all) if [ "$MENU_MODE" = "multi" ]; then i=0; while [ "$i" -lt "$MENU_N" ]; do MI_ON[i]=1; i=$((i + 1)); done; fi ;;
      none) if [ "$MENU_MODE" = "multi" ]; then i=0; while [ "$i" -lt "$MENU_N" ]; do MI_ON[i]=0; i=$((i + 1)); done; fi ;;
      enter) break ;;
      eof) menu_restore; trap - INT TERM HUP EXIT; die "Input closed while a menu was open." ;;
    esac
    menu_draw 0
  done
  menu_restore
  trap - INT TERM HUP EXIT
}

# ----------------------------------------------------------------------------- target architecture
# aarch64/arm64 is not offered yet (onpremise-webapp is published for amd64 only) - same policy as make-offline-zip.sh.
# SCLAB_OFFLINE_ARM64=1 lets you try it: the platform pre-check below then names every image without a linux/arm64 manifest.
ARM_SUPPORTED="${SCLAB_OFFLINE_ARM64:-0}"
if [ -z "$TARGET_ARCH" ]; then
  TARGET_ARCH="x86_64"
  if [ "$INTERACTIVE" = "1" ]; then
    info "Target CPU architecture: x86_64 (amd64). aarch64/arm64 is not supported yet."
  elif [ "$HOST_ARCH" != "x86_64" ]; then
    info "No --arch given: building for an x86_64 server (this machine is $HOST_OS/$HOST_ARCH; aarch64 targets are not supported yet)."
  fi
fi
case "$TARGET_ARCH" in
  x86_64|amd64) TARGET_ARCH=x86_64; PLATFORM="linux/amd64"; want_arch=amd64 ;;
  aarch64|arm64)
    if [ "$ARM_SUPPORTED" != "1" ]; then
      die "--arch $TARGET_ARCH is not supported yet (the onpremise-webapp image is amd64-only until a multi-arch image is published to ECR). Use --arch x86_64. To try aarch64 anyway: SCLAB_OFFLINE_ARM64=1 (the script then checks every selected image for a linux/arm64 manifest and stops naming the ones that lack it)."
    fi
    TARGET_ARCH=aarch64; PLATFORM="linux/arm64"; want_arch=arm64 ;;
  *) die "Unsupported --arch '$TARGET_ARCH' (x86_64; aarch64 is not supported yet)." ;;
esac
info "Host: $HOST_OS/$HOST_ARCH | Target server: Linux, architecture=$TARGET_ARCH ($PLATFORM)"

# ----------------------------------------------------------------------------- service selection
SELECTED=""   # space separated services
is_selected() { case " $SELECTED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
toggle() { if is_selected "$1"; then SELECTED="$(echo " $SELECTED " | sed "s/ $1 / /" | xargs)"; else SELECTED="$SELECTED $1"; fi; SELECTED="${SELECTED# }"; }
is_known_service() { case " $SVC_ALL " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

if [ -n "$SERVICES_ARG" ]; then
  for s in $(echo "$SERVICES_ARG" | tr ',' ' '); do
    is_known_service "$s" || die "Unknown service '$s'. Use --list-services."
    is_selected "$s" || toggle "$s"
  done
else
  SELECTED="webapp"
  if [ "$INTERACTIVE" = "1" ] && [ "$USE_ARROWS" = "1" ]; then
    MI_LABEL=(); MI_DESC=(); MI_ON=()
    for s in $SVC_ALL; do
      MI_LABEL+=("$s"); MI_DESC+=("$(svc_desc "$s")")
      if is_selected "$s"; then MI_ON+=(1); else MI_ON+=(0); fi
    done
    arrow_menu multi "Services to update (their images go into the update bundle)" "" 2
    SELECTED=""; k=0
    for s in $SVC_ALL; do [ "${MI_ON[$k]}" = "1" ] && SELECTED="$SELECTED $s"; k=$((k + 1)); done
    SELECTED="${SELECTED# }"
  elif [ "$INTERACTIVE" = "1" ]; then
    while true; do
      printf '\nServices to update (their images go into the update bundle)\n'
      printf '  Type a number to toggle:\n'
      n=0
      for s in $SVC_ALL; do
        n=$((n + 1))
        if is_selected "$s"; then box="[x]"; else box="[ ]"; fi
        printf '   %2d) %s %-16s %s\n' "$n" "$box" "$s" "$(svc_desc "$s")"
      done
      printf '  a = select all, n = select none, Enter = continue: '
      IFS= read -r a || a=""
      case "$a" in
        "") break ;;
        a|A) SELECTED="$SVC_ALL" ;;
        n|N) SELECTED="" ;;
        *)
          for tok in $(echo "$a" | tr ',' ' '); do
            case "$tok" in
              ''|*[!0-9]*) echo "Ignoring '$tok'." ;;
              *) k=0; found=""
                 for s in $SVC_ALL; do k=$((k + 1)); [ "$k" = "$tok" ] && found="$s"; done
                 if [ -n "$found" ]; then toggle "$found"; else echo "No such number: $tok"; fi ;;
            esac
          done ;;
      esac
    done
  fi
fi
if is_selected vision-gpu && ! is_selected vision; then warn "vision-gpu is selected without vision: only the GPU image is updated."; fi
[ -n "$SELECTED" ] || die "No service selected. Nothing to do."
ALL_SERVICES="$(echo "$SELECTED" | xargs)"
info "Services in the update bundle: $ALL_SERVICES"
if is_selected tileserver; then warn "tileserver is selected: the bundle will be ~95 GB or more. Make sure you have roughly 2.5x that in free disk space."; fi

# ----------------------------------------------------------------------------- bundle name, directories
case "$BUNDLE_NAME" in *[!A-Za-z0-9._-]*) die "--name may only contain letters, digits, '.', '_' and '-'." ;; esac
[ -n "$BUNDLE_NAME" ] || BUNDLE_NAME="sclab-update-$(date +%Y%m%d-%H%M%S)-${TARGET_ARCH}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
if ls "$OUT_DIR/$BUNDLE_NAME".* >/dev/null 2>&1; then
  die "$OUT_DIR already contains files of '$BUNDLE_NAME'. Remove them or pass another --name / --out."
fi
[ -n "$WORK_DIR" ] || WORK_DIR="$OUT_DIR/.work-$BUNDLE_NAME"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
STAGE="$WORK_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/images"

cleanup() {
  if [ "$KEEP_WORK" = "0" ] && [ -n "${WORK_DIR:-}" ] && [ -d "${WORK_DIR:-}" ]; then rm -rf "$WORK_DIR"; fi
}

# ----------------------------------------------------------------------------- image list from this repository
IMAGE_LIST="$WORK_DIR/images.list"   # "service<TAB>ref"
: > "$IMAGE_LIST"
for s in $ALL_SERVICES; do
  svc_images "$s" "$SCRIPT_DIR" | while IFS= read -r ref; do
    [ -n "$ref" ] && printf '%s\t%s\n' "$s" "$ref"
  done >> "$IMAGE_LIST"
done
[ -s "$IMAGE_LIST" ] || die "No images found for the selected services."
UNIQ_REFS="$(cut -f2 "$IMAGE_LIST" | sort -u)"

# ----------------------------------------------------------------------------- docker on the build machine
dk() { if [ -n "${DOCKER_SUDO:-}" ]; then $DOCKER_SUDO docker "$@"; else docker "$@"; fi; }
DOCKER_SUDO=""
ensure_build_docker() {
  if [ "$HOST_OS" = "Darwin" ]; then
    if ! command_exists docker; then
      die "Docker is not installed. Install Docker Desktop (https://www.docker.com/products/docker-desktop/), OrbStack (brew install --cask orbstack) or Colima (brew install colima docker && colima start), start it, and run this script again."
    fi
    if ! docker info >/dev/null 2>&1; then
      die "The Docker engine is not running. Start Docker Desktop / OrbStack (or: colima start) and run this script again. (docker context: $(docker context show 2>/dev/null || echo unknown))"
    fi
    ok "Docker: $(docker --version) (engine: $(docker info --format '{{.OperatingSystem}} {{.Architecture}}' 2>/dev/null || echo unknown))"
    return 0
  fi
  if ! command_exists docker; then
    warn "Docker is not installed on this (build) machine; it is needed for docker pull / docker save."
    local a
    if [ "$INTERACTIVE" = "1" ]; then
      printf 'Try to install it with the OS package manager now? [Y/n]: '
      IFS= read -r a || a=""
    else a="y"; fi
    case "${a:-Y}" in
      [Yy]*|"")
        if command_exists apt-get; then pkg_install docker.io || true
        elif command_exists dnf || command_exists yum; then pkg_install docker || pkg_install moby-engine || true
        else pkg_install docker || true; fi ;;
    esac
    command_exists docker || die "Docker is required. Install it (https://docs.docker.com/engine/install/) and run this script again."
  fi
  if ! docker info >/dev/null 2>&1; then
    if [ -n "$SUDO" ] && $SUDO docker info >/dev/null 2>&1; then DOCKER_SUDO="$SUDO"; warn "Using sudo for docker."
    else
      if command_exists systemctl; then $SUDO systemctl start docker >/dev/null 2>&1 || true; fi
      if docker info >/dev/null 2>&1; then :
      elif [ -n "$SUDO" ] && $SUDO docker info >/dev/null 2>&1; then DOCKER_SUDO="$SUDO"
      else die "Cannot reach the Docker daemon. Start it and check your permissions (docker group / sudo)."; fi
    fi
  fi
  ok "Docker: $(dk --version)"
}

# ----------------------------------------------------------------------------- AWS CLI (only needed to pull ECR images)
install_aws_cli_macos() {
  local tmp choices dest bindir
  if command_exists brew; then
    info "Installing the AWS CLI with Homebrew (brew install awscli)"
    brew install awscli && command_exists aws && return 0
    warn "brew install awscli failed; trying the official installer."
  fi
  # Official universal .pkg installed for the current user only (no sudo): ~/.local/aws-cli + symlink in ~/.local/bin
  tmp="$(mktemp -d)"; dest="$HOME/.local/aws-cli"; bindir="$HOME/.local/bin"
  mkdir -p "$dest" "$bindir"
  choices="$tmp/choices.xml"
  cat > "$choices" <<EOC
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
<key>choiceAttribute</key><string>customLocation</string>
<key>attributeSetting</key><string>$dest</string>
<key>choiceIdentifier</key><string>default</string>
</dict></array></plist>
EOC
  if download "https://awscli.amazonaws.com/AWSCLIV2.pkg" "$tmp/AWSCLIV2.pkg" \
     && installer -pkg "$tmp/AWSCLIV2.pkg" -target CurrentUserHomeDirectory -applyChoiceChangesXML "$choices" >/dev/null \
     && ln -sf "$dest/aws-cli/aws" "$bindir/aws"; then
    rm -rf "$tmp"
    export PATH="$bindir:$PATH"
    command_exists aws && return 0
  fi
  rm -rf "$tmp"
  warn "Could not install the AWS CLI automatically. Install it with 'brew install awscli' or from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html and run again."
  return 1
}

install_aws_cli() {
  if [ "$HOST_OS" = "Darwin" ]; then install_aws_cli_macos; return; fi
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

# ----------------------------------------------------------------------------- pull + save images
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
safe_name() { printf '%s' "$1" | sed 's#[^A-Za-z0-9._-]#_#g'; }
dash() { if [ -n "$1" ]; then printf '%s' "$1"; else printf '%s' "-"; fi; }   # empty TSV fields would collapse on read

NEEDS_ECR=0
if [ "$NO_PULL" = "0" ] && printf '%s\n' "$UNIQ_REFS" | grep -q '\.dkr\.ecr\.'; then NEEDS_ECR=1; fi
ensure_build_docker
if [ "$NEEDS_ECR" = "1" ]; then ecr_login; fi

# Platform pre-check (no image data is downloaded): a multi-platform manifest list must contain the target platform.
if [ "$NO_PULL" = "0" ]; then
  info "Checking that every image has a $PLATFORM manifest"
  NO_PLATFORM=""
  for ref in $UNIQ_REFS; do
    mf="$(dk manifest inspect "$ref" 2>&1)" || { warn "Could not read the manifest of $ref (will be checked when pulling): $(printf '%s' "$mf" | head -n1)"; continue; }
    if printf '%s' "$mf" | grep -q '"manifests"'; then
      if ! printf '%s' "$mf" | tr -d ' \n' | grep -q "\"architecture\":\"$want_arch\",\"os\":\"linux\""; then
        svcs="$(awk -F'\t' -v r="$ref" '$2 == r { printf "%s%s", (n++ ? "," : ""), $1 }' "$IMAGE_LIST")"
        err "$ref has no $PLATFORM manifest (used by: $svcs)."
        NO_PLATFORM="$NO_PLATFORM $ref"
      fi
    else
      one="$(dk buildx imagetools inspect --format '{{json .Image}}' "$ref" 2>/dev/null | tr -d ' \n' | sed -n 's/.*"architecture":"\([^"]*\)","os":"\([^"]*\)".*/\2\/\1/p')" || one=""
      if [ -n "$one" ] && [ "$one" != "linux/$want_arch" ]; then
        svcs="$(awk -F'\t' -v r="$ref" '$2 == r { printf "%s%s", (n++ ? "," : ""), $1 }' "$IMAGE_LIST")"
        err "$ref is published only for $one, not $PLATFORM (used by: $svcs)."
        NO_PLATFORM="$NO_PLATFORM $ref"
      fi
    fi
  done
  [ -z "$NO_PLATFORM" ] || die "These images are not published for $PLATFORM:$NO_PLATFORM
A bundle with images of another architecture would not run on the target. Deselect the services that use them or build for the architecture the images support (x86_64)."
fi

IMAGES_TSV="$STAGE/images.tsv"   # ref<TAB>image id<TAB>file<TAB>repo digest<TAB>size bytes<TAB>service(s)<TAB>created ("-" = empty)
: > "$IMAGES_TSV"
total="$(printf '%s\n' "$UNIQ_REFS" | wc -l | tr -d ' ')"
idx=0
TOTAL_BYTES=0
ARCH_MISMATCH=""
INSPECT_PLAT=""
if dk image inspect --help 2>&1 | grep -q -- '--platform'; then INSPECT_PLAT="--platform $PLATFORM"; fi
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
  # shellcheck disable=SC2086
  img_arch="$(dk image inspect $INSPECT_PLAT -f '{{.Architecture}}' "$ref" 2>/dev/null || echo unknown)"
  if [ "$img_arch" != "$want_arch" ]; then
    err "$ref only exists for '$img_arch', but the target architecture is '$want_arch'."
    ARCH_MISMATCH="$ARCH_MISMATCH $ref"
  fi
  # shellcheck disable=SC2086
  id="$(dk image inspect $INSPECT_PLAT -f '{{.Id}}' "$ref")"
  # shellcheck disable=SC2086
  digest="$(dk image inspect $INSPECT_PLAT -f '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$ref" 2>/dev/null || true)"
  # shellcheck disable=SC2086
  size="$(dk image inspect $INSPECT_PLAT -f '{{.Size}}' "$ref" 2>/dev/null || echo 0)"
  # shellcheck disable=SC2086
  created="$(dk image inspect $INSPECT_PLAT -f '{{.Created}}' "$ref" 2>/dev/null || true)"
  TOTAL_BYTES=$((TOTAL_BYTES + size))
  fname="$(printf '%03d' "$idx")-$(safe_name "$ref").tar"
  svcs="$(awk -F'\t' -v r="$ref" '$2 == r { printf "%s%s", (n++ ? "," : ""), $1 }' "$IMAGE_LIST")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ref" "$id" "$fname" "$(dash "$digest")" "$size" "$svcs" "$(dash "$created")" >> "$IMAGES_TSV"
done
if [ -n "$ARCH_MISMATCH" ]; then
  die "These images are not available for $TARGET_ARCH:$ARCH_MISMATCH
A bundle with images of another architecture would not run on the target. Deselect the services that use them or build for the architecture the images support (x86_64)."
fi

# Disk space check (before the big export): staged tars + final parts ~ 2x the image size.
need_kb=$(( (TOTAL_BYTES / 1024) * 21 / 10 ))
have_kb="$(df -Pk "$WORK_DIR" | awk 'NR==2 {print $4}')"
info "Images total about $((TOTAL_BYTES / 1024 / 1024)) MB; free space in $WORK_DIR: $((have_kb / 1024)) MB; needed about $((need_kb / 1024)) MB"
[ "$have_kb" -ge "$need_kb" ] || die "Not enough free disk space in $WORK_DIR. Free some space or use --work-dir / --out on a bigger disk."
if [ "$(df -Pk "$OUT_DIR" | awk 'NR==2 {print $1}')" != "$(df -Pk "$WORK_DIR" | awk 'NR==2 {print $1}')" ]; then
  have_out_kb="$(df -Pk "$OUT_DIR" | awk 'NR==2 {print $4}')"
  [ "$have_out_kb" -ge $(( TOTAL_BYTES * 11 / 10 / 1024 )) ] || die "Not enough free disk space in $OUT_DIR for the archive parts."
fi

idx=0
while IFS="$(printf '\t')" read -r ref _id fname _digest _size _svcs _created; do
  idx=$((idx + 1))
  info "[$idx/$total] docker save $ref"
  # Save exactly the target platform (the Docker engine may hold several, e.g. an amd64 pull on an Apple Silicon Mac).
  if dk save --help 2>&1 | grep -q -- '--platform'; then
    dk save --platform "$PLATFORM" -o "$STAGE/images/$fname" "$ref" || die "docker save failed for $ref"
  else
    dk save -o "$STAGE/images/$fname" "$ref" || die "docker save failed for $ref"
  fi
  if [ -n "$SUDO" ] && [ -n "$DOCKER_SUDO" ]; then $SUDO chown "$(id -u):$(id -g)" "$STAGE/images/$fname" 2>/dev/null || true; fi
done < "$IMAGES_TSV"

# ----------------------------------------------------------------------------- optional compose / script snapshot
export COPYFILE_DISABLE=1   # macOS: no AppleDouble "._*" files in the archive
TAR_META=""
if tar --version 2>&1 | grep -qi bsdtar; then
  TAR_META="--uid 0 --gid 0 --uname root --gname root"
  if tar --no-xattrs -cf /dev/null /dev/null 2>/dev/null; then TAR_META="$TAR_META --no-xattrs"; fi
else
  TAR_META="--owner=0 --group=0 --numeric-owner"
fi
GIT_REV="unknown"
if command_exists git && git -C "$SCRIPT_DIR" rev-parse --short HEAD >/dev/null 2>&1; then GIT_REV="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"; fi

if [ "$WITH_COMPOSE" = "1" ]; then
  info "Staging a snapshot of the repository's compose / script / config files (--with-compose)"
  mkdir -p "$STAGE/repo"
  # Never packed: VCS data, runtime state, secrets/certificates, installed settings, output dirs.
  (
    cd "$SCRIPT_DIR"
    tar -cf - --exclude='./.git' --exclude='./data' --exclude='./cert' --exclude='./jwt' --exclude='./.init' \
      --exclude='./.offline' --exclude='./.offline-updates' --exclude='*.bak' --exclude='./vision/data' --exclude='./vision/.env' \
      --exclude='./.env' --exclude='./settings.json' \
      --exclude='./sclab-offline-out' --exclude='./sclab-update-out' --exclude='./node_modules' --exclude='._*' --exclude='.DS_Store' \
      --exclude='./k8s' --exclude='./img' --exclude='./samples' . 2>/dev/null
  ) | (cd "$STAGE/repo" && tar -xf -)
  chmod +x "$STAGE/repo"/*.sh "$STAGE/repo"/*/*.sh 2>/dev/null || true
  # The installed compose files never pull from a registry (pull_policy: never), exactly like the full bundle.
  for f in "$STAGE"/repo/docker-compose.yml "$STAGE"/repo/gen.yml "$STAGE"/repo/optional-services/*.yml "$STAGE"/repo/gotenberg/*.yml \
           "$STAGE"/repo/tileserver/*.yml "$STAGE"/repo/vision/docker-compose*.yml "$STAGE"/repo/ollama/*.yml \
           "$STAGE"/repo/speaches/*.yaml "$STAGE"/repo/vllm/*.yml; do
    [ -f "$f" ] || continue
    awk '
      { print }
      match($0, /^ +image:[ \t]/) {
        ind = substr($0, 1, RLENGTH - 7)
        sub(/[^ ].*$/, "", ind)
        print ind "pull_policy: never"
      }
    ' "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
  done
fi

# ----------------------------------------------------------------------------- base bundle link, manifest
BASE_NAME=""; BASE_REV=""
if [ -n "$BASE_MANIFEST_ARG" ]; then
  [ -r "$BASE_MANIFEST_ARG" ] || die "Cannot read --base-manifest file: $BASE_MANIFEST_ARG"
  BASE_NAME="$(sed -n 's/^  "bundle_name": "\([^"]*\)".*/\1/p' "$BASE_MANIFEST_ARG" | head -1)"
  BASE_REV="$(sed -n 's/^  "repo_revision": "\([^"]*\)".*/\1/p' "$BASE_MANIFEST_ARG" | head -1)"
  [ -n "$BASE_NAME" ] || die "--base-manifest: no bundle_name found in $BASE_MANIFEST_ARG."
fi
if [ -n "$BASE_BUNDLE_ARG" ]; then BASE_NAME="$BASE_BUNDLE_ARG"; fi

CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "BUNDLE_KIND=update"
  echo "BUNDLE_NAME=$BUNDLE_NAME"
  echo "CREATED_AT=$CREATED_AT"
  echo "TARGET_ARCH=$TARGET_ARCH"
  echo "SERVICES=\"$ALL_SERVICES\""
  echo "IMAGES_BYTES=$TOTAL_BYTES"
  echo "WITH_COMPOSE=$WITH_COMPOSE"
} > "$STAGE/bundle.env"

write_manifest() { # $1 = output path; $2 = parts list file (may be empty)
  local out="$1" parts="$2" first=1 svc_json="" s p
  for s in $ALL_SERVICES; do svc_json="$svc_json${svc_json:+, }\"$s\""; done
  {
    echo "{"
    echo "  \"bundle_kind\": \"update\","
    echo "  \"format_version\": 1,"
    echo "  \"bundle_name\": \"$(json_escape "$BUNDLE_NAME")\","
    echo "  \"created_at\": \"$CREATED_AT\","
    echo "  \"repo_revision\": \"$(json_escape "$GIT_REV")\","
    echo "  \"target_arch\": \"$TARGET_ARCH\","
    echo "  \"platform\": \"$PLATFORM\","
    echo "  \"with_compose\": $([ "$WITH_COMPOSE" = "1" ] && echo true || echo false),"
    echo "  \"license_included\": false,"
    echo "  \"base_bundle\": \"$(json_escape "$BASE_NAME")\","
    echo "  \"base_repo_revision\": \"$(json_escape "$BASE_REV")\","
    echo "  \"images_bytes\": $TOTAL_BYTES,"
    echo "  \"services\": [$svc_json],"
    echo "  \"images\": ["
    while IFS="$(printf '\t')" read -r ref id fname digest size svcs created; do
      [ "$first" = "1" ] || echo ","
      first=0
      [ "$digest" != "-" ] || digest=""
      [ "$created" != "-" ] || created=""
      printf '    {"ref": "%s", "id": "%s", "repo_digest": "%s", "created": "%s", "size_bytes": %s, "services": "%s", "file": "images/%s"}' \
        "$(json_escape "$ref")" "$id" "$(json_escape "$digest")" "$created" "${size:-0}" "$svcs" "$fname"
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
write_manifest "$STAGE/MANIFEST.inner.json" ""

# ----------------------------------------------------------------------------- tar | gzip | split
COMPRESS="gzip -1"
if command_exists pigz; then COMPRESS="pigz -1"; fi
info "Creating the archive and splitting it into ${PART_SIZE_MB} MB parts (compressor: ${COMPRESS%% *})"
PART_BYTES=$((PART_SIZE_MB * 1024 * 1024))
PREFIX="$OUT_DIR/$BUNDLE_NAME.tar.gz.part"
# shellcheck disable=SC2086
( cd "$STAGE" && tar $TAR_META -cf - . ) | $COMPRESS | split -a 4 -b "$PART_BYTES" - "$PREFIX.tmp_"
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

write_manifest "$OUT_DIR/$BUNDLE_NAME.MANIFEST.json" "$PARTS_LIST"
if cp "$SCRIPT_DIR/update-offline-images.sh" "$OUT_DIR/update-offline-images.sh" 2>/dev/null; then
  chmod +x "$OUT_DIR/update-offline-images.sh"
else
  warn "update-offline-images.sh not found next to this script: copy it to the server yourself."
fi

info "Computing SHA256SUMS"
(
  cd "$OUT_DIR"
  # shellcheck disable=SC2046
  $SHA256 $(cat "$PARTS_LIST") "$BUNDLE_NAME.MANIFEST.json" > "$BUNDLE_NAME.SHA256SUMS"
)
ok "$BUNDLE_NAME.SHA256SUMS written"

cleanup

echo
echo "================================================================"
echo " Update bundle ready: $OUT_DIR"
echo "================================================================"
( cd "$OUT_DIR" && for f in "$BUNDLE_NAME".* update-offline-images.sh; do [ -f "$f" ] && ls -lh "$f"; done | sed 's/^/  /' )
cat <<EOF

Next steps:
  1. Copy these files to the air-gapped server, into one directory (other update bundles may be there too):
       $BUNDLE_NAME.tar.gz.part*, $BUNDLE_NAME.SHA256SUMS, $BUNDLE_NAME.MANIFEST.json, update-offline-images.sh
  2. On the server (as root):   sudo bash ./update-offline-images.sh     (--help for all options)

Bundle: $BUNDLE_NAME | arch: $TARGET_ARCH | services: $ALL_SERVICES | compose snapshot: $([ "$WITH_COMPOSE" = "1" ] && echo yes || echo no)
EOF
