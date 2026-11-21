#!/usr/bin/env bash
# make-offline-zip.sh - build an offline (air-gapped) install bundle for SCLAB Studio.
#
# Run this on a Linux or macOS (Intel / Apple Silicon) machine WITH internet access. It
#   1. asks for the target OS family and the services to include (checkbox menu); the target is always x86_64 (amd64),
#   2. installs the AWS CLI if it is missing and logs in to the private ECR registry,
#   3. downloads the Docker Engine (static binaries) and the Docker Compose plugin for the target,
#   4. pulls every selected image (docker pull) and exports it (docker save),
#   5. stores this repository (scripts, compose, env files) and the license key in the bundle,
#   6. writes ONE compressed archive optionally split into parts (default 1 GB: *.part001 ...; --no-split / --part-size) + SHA256SUMS + MANIFEST.json
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
PART_SIZE_ARG=""
NO_SPLIT=0
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
(runs on Linux or macOS; the bundle is for a LINUX server - see --os / --arch)

Usage: ./make-offline-zip.sh [options]

Without options the script is interactive (arrow-key menus for the OS family and the services:
Up/Down or j/k move, Space toggles, Enter confirms; numeric prompts when there is no terminal).

Options:
  -y, --yes                 Non-interactive: use defaults for everything not given as an option.
  --os NAME                 Target OS family: ubuntu | rhel | amzn | suse | alpine | generic
                              ubuntu = Ubuntu/Debian, rhel = RHEL/Rocky/Alma/CentOS/Oracle/Fedora,
                              amzn = Amazon Linux, suse = SUSE/openSUSE, alpine = Alpine, generic = other.
  --arch ARCH               Target architecture: x86_64 (amd64) only - the default. Other values are an error.
  --services LIST           Comma separated OPTIONAL services to include (required ones are always included).
                              "none" = only the required ones. See --list-services.
  --list-services           Print the service catalog and exit.
  --out DIR                 Output directory (default: ./sclab-offline-out)
  --name NAME               Bundle name (default: sclab-offline-<date>-<arch>)
  --part-size SIZE          Split the archive into parts of SIZE: 500M, 2G (MB/GB), a bare number = MB (e.g. 1024).
                              Whole numbers only. Default: 1G. Interactive runs ask for the splitting mode.
  --no-split                Do not split: write ONE single archive file.
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
  ' "$1" | sed 's/\${[A-Za-z_][A-Za-z0-9_]*:-\([^}]*\)}/\1/g'   # ${VAR:-default} -> default
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
# Part size argument: digits with an optional unit: 500 / 500M / 500MB (MB, the historical meaning of a bare number), 2G / 2GB.
parse_part_size() { # $1 = value -> SPLIT_MODE (gb|mb) and SPLIT_SIZE; returns 1 when the value is not valid
  local v n u
  v="$(printf '%s' "$1" | tr 'a-z' 'A-Z')"
  n="${v%%[!0-9]*}"; u="${v#"$n"}"
  case "$u" in ''|M|MB|MIB) u=mb ;; G|GB|GIB) u=gb ;; *) return 1 ;; esac
  n="$(printf '%s' "$n" | sed 's/^0*//')"
  [ -n "$n" ] && [ "${#n}" -le 9 ] || return 1
  SPLIT_MODE="$u"; SPLIT_SIZE="$n"
}

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
    --part-size) PART_SIZE_ARG="${2:-}"; shift ;;
    --no-split) NO_SPLIT=1 ;;
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

SPLIT_MODE=""; SPLIT_SIZE=0; PART_BYTES=0
if [ "$NO_SPLIT" = "1" ]; then
  [ -z "$PART_SIZE_ARG" ] || die "--no-split and --part-size cannot be used together."
  SPLIT_MODE=none
elif [ -n "$PART_SIZE_ARG" ]; then
  parse_part_size "$PART_SIZE_ARG" || die "--part-size must be a positive whole number with an optional unit, e.g. 500M, 2G or 1024 (no unit = MB); got '$PART_SIZE_ARG'."
fi

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

# Host package manager (used only to install missing helper tools such as unzip / docker / awscli).
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

# Make sure the basic tools exist; install the missing ones with the package manager (this machine has internet).
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
if command_exists sha256sum; then SHA256="sha256sum"
elif command_exists shasum; then SHA256="shasum -a 256"
fi

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

# Arrow-key menus: need a real terminal on stdin and stderr. Pipes/CI, TERM=dumb or an unset TERM use the numeric prompts instead.
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

# Draws (or redraws in place) the menu. Items come from the arrays MI_LABEL / MI_DESC / MI_ON; MENU_CUR is the cursor row (0-based).
menu_draw() { # $1 = 1 on the first draw
  local i mark plain
  [ "$1" = "1" ] || printf '\033[%dA' "$MENU_LINES" >&2
  printf '\r\033[K%s\n' "$MENU_TITLE" >&2
  if [ -n "$MENU_HEADER" ]; then printf '\r\033[K%s\n' "${MENU_HEADER:0:$((TERM_COLS - 1))}" >&2; fi
  i=0
  while [ "$i" -lt "$MENU_N" ]; do
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
  printf '\r\033[K%s\n' "${MENU_FOOTER:0:$((TERM_COLS - 1))}" >&2
}

# $1 = multi|single, $2 = title, $3 = header line (may be empty), $4 = initial cursor row (0-based).
# Items in MI_LABEL / MI_DESC / MI_ON. multi: result is left in MI_ON; single: the chosen row is left in MENU_CUR.
arrow_menu() {
  local i
  MENU_MODE="$1"; MENU_TITLE="$2"; MENU_HEADER="$3"; MENU_CUR="$4"; MENU_N="${#MI_LABEL[@]}"
  MENU_LINES=$((MENU_N + 2)); [ -n "$MENU_HEADER" ] && MENU_LINES=$((MENU_LINES + 1))
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

# Single choice: $1 title, $2 default index (1-based), rest labels -> echoes the chosen index (1-based).
# Arrow-key menu on a terminal, numeric prompt otherwise.
choose_one() {
  local title="$1" def="$2"
  shift 2
  if [ "$USE_ARROWS" = "1" ] && [ "$(($# + 4))" -le "$TERM_ROWS" ]; then
    MI_LABEL=("$@"); MI_DESC=(); MI_ON=()
    arrow_menu single "$title" "" "$((def - 1))" >&2
    echo "$((MENU_CUR + 1))"
  else
    ask_choice "$title" "$def" "$@"
  fi
}

# ----------------------------------------------------------------------------- target OS / arch
if [ -z "$TARGET_OS" ]; then
  if [ "$INTERACTIVE" = "1" ]; then
    idx="$(choose_one "Target server OS family (the offline server where SCLAB will be installed):" 1 \
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

# Only x86_64 (amd64) servers are supported: there is no architecture menu and images are always pulled as linux/amd64.
# The machine that builds the bundle may be anything (e.g. an Apple Silicon Mac) - only the TARGET is fixed.
[ -n "$TARGET_ARCH" ] || TARGET_ARCH="x86_64"
case "$TARGET_ARCH" in
  x86_64|amd64) TARGET_ARCH=x86_64; PLATFORM="linux/amd64" ;;
  *) die "--arch '$TARGET_ARCH': only x86_64 (amd64) is supported." ;;
esac
info "Host: $HOST_OS/$HOST_ARCH | Target server: Linux, OS family=$TARGET_OS, architecture=$TARGET_ARCH ($PLATFORM)"

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
  if [ "$INTERACTIVE" = "1" ] && [ "$USE_ARROWS" = "1" ] && [ "$(( $(echo "$SVC_OPTIONAL" | wc -w) + 6 ))" -le "$TERM_ROWS" ]; then
    MI_LABEL=(); MI_DESC=(); MI_ON=()
    for s in $SVC_OPTIONAL; do
      MI_LABEL+=("$s"); MI_DESC+=("$(svc_desc "$s")")
      if is_selected "$s"; then MI_ON+=(1); else MI_ON+=(0); fi
    done
    arrow_menu multi "Services to include in the bundle" "  [x] LOCKED, always included: $SVC_REQUIRED" 0
    SELECTED=""; k=0
    for s in $SVC_OPTIONAL; do [ "${MI_ON[$k]}" = "1" ] && SELECTED="$SELECTED $s"; k=$((k + 1)); done
    SELECTED="${SELECTED# }"
  elif [ "$INTERACTIVE" = "1" ]; then
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

# ----------------------------------------------------------------------------- archive splitting
# SPLIT_MODE: none (one single file) | gb | mb (parts of SPLIT_SIZE GB / MB). Default: gb, 1  (= 1 GB parts).
ask_split_size() { # $1 = gb|mb, $2 = default -> sets SPLIT_SIZE (positive whole number; asks again on bad input)
  local unit="$1" def="$2" a UNIT_UP
  UNIT_UP="$(printf '%s' "$unit" | tr 'a-z' 'A-Z')"
  while true; do
    printf 'Part size in %s [%s]: ' "$UNIT_UP" "$def" >&2
    IFS= read -r a || a=""
    a="${a:-$def}"
    case "$a" in
      ''|*[!0-9]*) echo "Please enter a positive whole number (digits only, no decimals or units)." >&2; continue ;;
    esac
    a="$(printf '%s' "$a" | sed 's/^0*//')"
    if [ -z "$a" ] || [ "${#a}" -gt 9 ]; then echo "The size must be between 1 and 999999999 $UNIT_UP." >&2; continue; fi
    SPLIT_SIZE="$a"
    return 0
  done
}

ask_split_mode() {
  local idx
  MI_LABEL=("Do not split (one single file)" "Split into parts, size in GB   (default: 1 GB)" "Split into parts, size in MB   (default: 1024 MB)")
  MI_DESC=(); MI_ON=()
  if [ "$USE_ARROWS" = "1" ] && [ "$((${#MI_LABEL[@]} + 5))" -le "$TERM_ROWS" ]; then
    arrow_menu single "Archive splitting (a part size larger than the whole bundle gives one single file anyway):" "" 1 >&2
    idx="$((MENU_CUR + 1))"
  else
    printf '\nArchive splitting (a part size larger than the whole bundle gives one single file anyway):\n' >&2
    printf '  1) %s\n  2) %s\n  3) %s\n' "${MI_LABEL[0]}" "${MI_LABEL[1]}" "${MI_LABEL[2]}" >&2
    while true; do
      printf 'Select [1-3, Enter = 2]: ' >&2
      IFS= read -r idx || idx=""
      idx="${idx:-2}"
      case "$idx" in 1|2|3) break ;; esac
      echo "Invalid choice." >&2
    done
  fi
  case "$idx" in
    1) SPLIT_MODE=none; SPLIT_SIZE=0 ;;
    2) SPLIT_MODE=gb; ask_split_size gb 1 ;;
    *) SPLIT_MODE=mb; ask_split_size mb 1024 ;;
  esac
}

if [ -z "$SPLIT_MODE" ]; then
  if [ "$INTERACTIVE" = "1" ]; then ask_split_mode; else SPLIT_MODE=gb; SPLIT_SIZE=1; fi
fi
case "$SPLIT_MODE" in
  none) PART_BYTES=0; info "Archive: one single file (no splitting)" ;;
  gb) PART_BYTES=$((SPLIT_SIZE * 1024 * 1024 * 1024)); info "Archive: split into parts of ${SPLIT_SIZE} GB (a smaller bundle becomes one single file)" ;;
  mb) PART_BYTES=$((SPLIT_SIZE * 1024 * 1024)); info "Archive: split into parts of ${SPLIT_SIZE} MB (a smaller bundle becomes one single file)" ;;
esac

# ----------------------------------------------------------------------------- output / work directories
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
[ -n "$WORK_DIR" ] || WORK_DIR="$OUT_DIR/.work"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
STAGE="$WORK_DIR/stage"
[ -n "$BUNDLE_NAME" ] || BUNDLE_NAME="sclab-offline-$(date +%Y%m%d)-${TARGET_ARCH}"
case "$BUNDLE_NAME" in *[!A-Za-z0-9._-]*) die "--name may only contain letters, digits, '.', '_' and '-'." ;; esac
if ls "$OUT_DIR/$BUNDLE_NAME".tar.gz* >/dev/null 2>&1; then
  die "$OUT_DIR already contains parts of '$BUNDLE_NAME'. Remove them or pass another --name / --out."
fi
rm -rf "$STAGE"
mkdir -p "$STAGE"/{repo,images,docker,license}

cleanup() {
  if [ "$KEEP_WORK" = "0" ] && [ -n "${STAGE:-}" ] && [ -d "${WORK_DIR:-}" ]; then rm -rf "$WORK_DIR"; rmdir "$OUT_DIR" 2>/dev/null || true; fi
}

# ----------------------------------------------------------------------------- stage the repository
info "Staging the repository files"
# macOS: do not store AppleDouble "._*" files / extended attributes in the archives.
export COPYFILE_DISABLE=1
TAR_META=""
if tar --version 2>&1 | grep -qi bsdtar; then
  # bsdtar (macOS): force root ownership; GNU tar below does the same with --owner/--group.
  TAR_META="--uid 0 --gid 0 --uname root --gname root"
  tar --no-xattrs -cf /dev/null /dev/null 2>/dev/null && TAR_META="$TAR_META --no-xattrs"
else
  TAR_META="--owner=0 --group=0 --numeric-owner"
fi
(
  cd "$SCRIPT_DIR"
  # Exclude VCS data, runtime state and secrets of a running installation, and the output/work directories.
  tar -cf - --exclude='./.git' --exclude='./data' --exclude='./cert' --exclude='./jwt' --exclude='./.init' \
    --exclude='./.offline' --exclude='*.bak' --exclude='./vision/data' --exclude='./vision/.env' \
    --exclude='./sclab-offline-out' --exclude='./node_modules' --exclude='._*' --exclude='.DS_Store' . 2>/dev/null
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

# ----------------------------------------------------------------------------- Docker Engine + Compose binaries for the target
# Why static binaries: the Docker static tarball (download.docker.com/linux/static) is one self-contained set of binaries
# (dockerd, containerd, runc, ...) per CPU architecture. Unlike .deb/.rpm packages it has no per-distro/per-version
# dependency chain (containerd.io, iptables, container-selinux, ...) that can break on an offline server whose package
# repositories are unreachable, and one download works on every glibc/musl distribution. install-offline.sh adds the
# service unit (systemd / OpenRC) itself.
fetch_docker_binaries() {
  local darch="x86_64" carch="x86_64"   # target is always x86_64 (amd64)
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

want_arch=amd64
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
ARCH_MISMATCH=""
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
  # inspect the target platform variant when the engine supports --platform (containerd image store)
  INSPECT_PLAT=""
  if dk image inspect --help 2>&1 | grep -q -- '--platform'; then INSPECT_PLAT="--platform $PLATFORM"; fi
  # shellcheck disable=SC2086
  img_arch="$(dk image inspect $INSPECT_PLAT -f '{{.Architecture}}' "$ref" 2>/dev/null || echo unknown)"
  if [ "$img_arch" != "$want_arch" ]; then
    err "$ref only exists for '$img_arch', but the target architecture is '$want_arch'."
    ARCH_MISMATCH="$ARCH_MISMATCH $ref"
  fi
  # shellcheck disable=SC2086
  id="$(dk image inspect $INSPECT_PLAT -f '{{.Id}}' "$ref")"
  digest="$(dk image inspect $INSPECT_PLAT -f '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$ref" 2>/dev/null || true)"
  size="$(dk image inspect $INSPECT_PLAT -f '{{.Size}}' "$ref" 2>/dev/null || echo 0)"
  TOTAL_BYTES=$((TOTAL_BYTES + size))
  fname="$(printf '%03d' "$idx")-$(safe_name "$ref").tar"
  svcs="$(awk -F'\t' -v r="$ref" '$2 == r { printf "%s%s", (n++ ? "," : ""), $1 }' "$IMAGE_LIST")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ref" "$id" "$fname" "$digest" "$size" "$svcs" >> "$IMAGES_TSV"
done

if [ -n "$ARCH_MISMATCH" ]; then
  die "These images are not available for linux/amd64:$ARCH_MISMATCH
Only x86_64 (amd64) servers are supported; a bundle with images of another architecture would not run on the target. Deselect the services that use them (with --no-pull, pull the images as linux/amd64 first)."
fi

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
  # Save exactly the target platform (the Docker engine may hold several, e.g. an amd64 pull on an Apple Silicon Mac).
  if dk save --help 2>&1 | grep -q -- '--platform'; then
    dk save --platform "$PLATFORM" -o "$STAGE/images/$fname" "$ref" || die "docker save failed for $ref"
  else
    dk save -o "$STAGE/images/$fname" "$ref" || die "docker save failed for $ref"
  fi
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
    echo "  \"split\": {\"mode\": \"$MANIFEST_SPLIT_MODE\", \"size\": $MANIFEST_SPLIT_SIZE},"
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
MANIFEST_SPLIT_MODE="$SPLIT_MODE"; MANIFEST_SPLIT_SIZE="$SPLIT_SIZE"
write_manifest "$STAGE/MANIFEST.json" ""
cp "$STAGE/MANIFEST.json" "$STAGE/MANIFEST.inner.json"

# ----------------------------------------------------------------------------- tar | gzip | split
COMPRESS="gzip -1"
command_exists pigz && COMPRESS="pigz -1"
PARTS_LIST="$WORK_DIR/parts.list"
: > "$PARTS_LIST"
SINGLE="$OUT_DIR/$BUNDLE_NAME.tar.gz"
PREFIX="$SINGLE.part"
if [ "$SPLIT_MODE" = "none" ]; then
  info "Creating the archive as one single file (compressor: ${COMPRESS%% *})"
  # shellcheck disable=SC2086
  ( cd "$STAGE" && tar $TAR_META -cf - . ) | $COMPRESS > "$SINGLE.tmp_" || die "Archive creation failed."
  mv "$SINGLE.tmp_" "$SINGLE"
  basename "$SINGLE" >> "$PARTS_LIST"
  ok "1 file written (no splitting)"
else
  info "Creating the archive and splitting it into ${SPLIT_SIZE} $(printf '%s' "$SPLIT_MODE" | tr a-z A-Z) parts (compressor: ${COMPRESS%% *})"
  # shellcheck disable=SC2086
  ( cd "$STAGE" && tar $TAR_META -cf - . ) | $COMPRESS | split -a 4 -b "$PART_BYTES" - "$PREFIX.tmp_"
  # rename aaaa,aaab,... -> 001,002,...
  n=0
  for f in "$PREFIX".tmp_*; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    new="$(printf '%s%03d' "$PREFIX" "$n")"
    mv "$f" "$new"
    basename "$new" >> "$PARTS_LIST"
  done
  [ "$n" -ge 1 ] || die "Archive creation produced no parts."
  if [ "$n" -eq 1 ]; then
    # The whole archive is smaller than one part: same result as "do not split" - a single file without the .part001 suffix.
    mv "${PREFIX}001" "$SINGLE"
    basename "$SINGLE" > "$PARTS_LIST"
    SPLIT_MODE=none; SPLIT_SIZE=0
    ok "The archive is smaller than the part size: written as one single file"
  else
    ok "$n part(s) written"
  fi
fi
MANIFEST_SPLIT_MODE="$SPLIT_MODE"; MANIFEST_SPLIT_SIZE="$SPLIT_SIZE"

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
       *.tar.gz or *.tar.gz.part*, SHA256SUMS, MANIFEST.json, install-offline.sh
  2. On the server (as root):   sudo bash ./install-offline.sh
     (add --yes for an unattended install with defaults; --help for all options)

Target: OS family=$TARGET_OS, arch=$TARGET_ARCH | services: $ALL_SERVICES
EOF
if [ -n "$LICENSE_KEY" ]; then
  echo "NOTE: the license key is stored in plain text inside the archive. Handle the files as confidential."
fi
