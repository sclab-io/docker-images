#!/usr/bin/env bash
# update-offline-images.sh - apply an UPDATE bundle (made by make-offline-update-zip.sh) to an installed, air-gapped SCLAB Studio.
#
# Put the update bundle files (<name>.tar.gz or <name>.tar.gz.part001 ..., <name>.SHA256SUMS, <name>.MANIFEST.json) of one or more update
# bundles in ONE directory on the server and run (as root, from that directory or with --dir):
#     sudo bash ./update-offline-images.sh
#
# What it does (no internet access is used at any point):
#   1. finds the update bundles in the directory (a menu is shown when there are several),
#   2. verifies the checksums and the CPU architecture, joins the parts and extracts them to a temporary directory,
#   3. loads the images (docker load) and compares them with the images the services run now (only changed services are updated),
#   4. after your confirmation: records rollback information (the previous images are kept as <repo>:rollback-<time>),
#      optionally merges the bundled compose/config files (--with-compose bundles), and applies the update:
#        webapp  - rolling: start the new container, wait, then stop the old one (like update.sh),
#        others  - docker compose up -d --no-deps <service>,
#   5. checks the health of the updated services; on failure the previous images are restored (or use --rollback later),
#   6. writes the history to <install dir>/.offline-updates/history.tsv (a bundle that was already applied is reported).
# It is safe to run again: unchanged services are not touched.
set -euo pipefail

# ----------------------------------------------------------------------------- defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR=""
INSTALL_DIR=""
ASSUME_YES=0
FORCE=0
DRY_RUN=0
APPLY_ALL=0
LIST_ONLY=0
NO_CONFIG=0
AUTO_ROLLBACK=1
KEEP_WORK=0
WORK_BASE=""
ROLLBACK_MODE=0
ROLLBACK_NAME=""
BUNDLE_ARGS=""
WAIT_SECS=30        # webapp: seconds the new container must run before the old one is stopped (update.sh waits 30 s too)
STABLE_SECS=10      # other services: seconds a container must stay up after it became ready
READY_TIMEOUT=180   # seconds to wait for a container to become running / healthy
HIST_DIRNAME=".offline-updates"

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
update-offline-images.sh - apply an update bundle (images, optionally config files) to an installed offline SCLAB Studio

Usage: sudo bash ./update-offline-images.sh [options]

  --dir DIR           Directory that holds the update bundle files (default: the current directory; if it has none,
                      this script's directory).
  --install-dir DIR   The installed docker-images directory (default: auto-detect: the current directory when it has a
                      docker-compose.yml, else /opt/sclab/docker-images).
  --bundle NAME       Apply this bundle (repeat or comma separate to apply several, always in date order).
  --all               Apply every bundle in the directory that was not applied yet, oldest first (no menu).
  --list              Only list the bundles found (with their applied status) and exit.
  -y, --yes           Unattended: no questions (a bundle that was already applied is skipped unless --force).
  --force             Apply a bundle again even if the history says it was applied already.
  --dry-run           Verify the checksums and show what would change; change nothing.
  --no-config         Do not merge the compose/config snapshot of a --with-compose bundle (images only).
  --no-auto-rollback  When the health check fails, do not restore the previous images automatically (default with
                      --yes is to roll back; interactively you are asked).
  --wait SECS         webapp rolling update: seconds the new container runs before the old one is stopped (default 30).
  --ready-timeout S   Seconds to wait for a container to become running/healthy (default 180).
  --work-dir DIR      Where the bundle is extracted temporarily (default: the bundle directory). Needs about the
                      size of the bundle's images.
  --keep-work         Keep the extracted files (for debugging).
  --rollback [NAME]   Go back to the images that ran before bundle NAME was applied (default: the most recently applied
                      one). Restores the config files that bundle changed, too.
  -h, --help          Show this help.

Applied bundles are recorded in <install dir>/.offline-updates/history.tsv. The previous images stay on the server as
<repository>:rollback-<time> tags; remove them yourself (docker image rm <tag>) when you no longer need them.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) SRC_DIR="${2:?--dir needs a value}"; shift ;;
    --install-dir) INSTALL_DIR="${2:?--install-dir needs a value}"; shift ;;
    --bundle) BUNDLE_ARGS="$BUNDLE_ARGS ${2:?--bundle needs a value}"; shift ;;
    --all) APPLY_ALL=1 ;;
    --list) LIST_ONLY=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --no-config) NO_CONFIG=1 ;;
    --no-auto-rollback) AUTO_ROLLBACK=0 ;;
    --wait) WAIT_SECS="${2:?--wait needs a value}"; shift ;;
    --ready-timeout) READY_TIMEOUT="${2:?--ready-timeout needs a value}"; shift ;;
    --work-dir) WORK_BASE="${2:?--work-dir needs a value}"; shift ;;
    --keep-work) KEEP_WORK=1 ;;
    --rollback)
      ROLLBACK_MODE=1
      if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then ROLLBACK_NAME="$2"; shift; fi ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done
BUNDLE_ARGS="$(printf '%s' "$BUNDLE_ARGS" | tr ',' ' ')"
case "$WAIT_SECS$READY_TIMEOUT" in ''|*[!0-9]*) die "--wait and --ready-timeout must be numbers of seconds." ;; esac

INTERACTIVE=1
if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then INTERACTIVE=0; fi

# ----------------------------------------------------------------------------- 1. checks
step "1. System checks"
[ "$(uname -s)" = "Linux" ] || die "This script supports Linux servers only (detected: $(uname -s))."
[ "$(id -u)" -eq 0 ] || die "Root privileges are required. Run: sudo bash ./update-offline-images.sh"
for c in tar gzip sed awk grep df cat sort date find; do
  command_exists "$c" || die "Required command not found: $c"
done
if command_exists sha256sum; then SHA_CHECK="sha256sum -c"
elif command_exists shasum; then SHA_CHECK="shasum -a 256 -c"
else die "sha256sum (or shasum) is required to verify the bundle."; fi
command_exists docker || die "Docker is not installed on this server."
docker info >/dev/null 2>&1 || die "The Docker daemon is not running (or not reachable). Start it and run this script again."
if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command_exists docker-compose; then DC="docker-compose"
else die "Docker Compose is not available (need 'docker compose' or docker-compose)."; fi
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64|amd64) HOST_ARCH=x86_64; HOST_DOCKER_ARCH=amd64 ;;
  aarch64|arm64) HOST_ARCH=aarch64; HOST_DOCKER_ARCH=arm64 ;;
  *) die "This server's CPU architecture is '$HOST_ARCH'. Supported: x86_64 (amd64) and aarch64 (arm64)." ;;
esac

# installed directory
if [ -z "$INSTALL_DIR" ]; then
  if [ -f "$PWD/docker-compose.yml" ]; then INSTALL_DIR="$PWD"
  elif [ -f /opt/sclab/docker-images/docker-compose.yml ]; then INSTALL_DIR="/opt/sclab/docker-images"
  elif [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then INSTALL_DIR="$SCRIPT_DIR"
  else die "Could not find the installed docker-images directory. Run this script from it or pass --install-dir DIR."; fi
fi
[ -f "$INSTALL_DIR/docker-compose.yml" ] || die "$INSTALL_DIR/docker-compose.yml not found: --install-dir must point to the installed docker-images directory."
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
if [ -f "$INSTALL_DIR/.offline" ]; then
  ok "Installation: $INSTALL_DIR (offline mode: .offline marker present)"
else
  warn "$INSTALL_DIR has no .offline marker: it does not look like an offline installation (install-offline.sh creates it)."
  if [ "$INTERACTIVE" = "1" ]; then
    printf 'Continue anyway? [y/N]: '; IFS= read -r a || a=""
    case "$a" in [Yy]*) ;; *) die "Cancelled." ;; esac
  elif [ "$FORCE" = "0" ]; then
    die "Refusing to continue unattended without the .offline marker. Pass --force to override."
  fi
fi
STATE_DIR="$INSTALL_DIR/$HIST_DIRNAME"
HISTORY="$STATE_DIR/history.tsv"
mkdir -p "$STATE_DIR"

# ----------------------------------------------------------------------------- helpers
human_size() { # bytes -> text
  awk -v b="${1:-0}" 'BEGIN { if (b >= 1073741824) printf "%.1f GB", b / 1073741824; else printf "%.0f MB", b / 1048576 }'
}
short_id() { local s="${1#sha256:}"; printf '%s' "${s:0:12}"; }
json_str() { # $1 file, $2 key: top-level string / number / bool of the pretty-printed MANIFEST.json
  sed -n "s/^  \"$2\": \"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\}\$/\1/p" "$1" | head -1
}
ref_repo() { local r="${1%@*}"; case "${r##*/}" in *:*) r="${r%:*}" ;; esac; printf '%s' "$r"; }
ask_yn() { # $1 prompt, $2 default (Y|N). --yes answers with the default... of "yes" for Y prompts, "no" for N prompts
  local a def="$2"
  if [ "$ASSUME_YES" = "1" ]; then [ "$def" = "Y" ]; return; fi
  [ "$INTERACTIVE" = "1" ] || die "This step needs a terminal for the question \"$1\". Use --yes for unattended runs."
  while true; do
    if [ "$def" = "Y" ]; then printf '%s [Y/n]: ' "$1"; else printf '%s [y/N]: ' "$1"; fi
    IFS= read -r a || a=""
    case "${a:-$def}" in [Yy]*) return 0 ;; [Nn]*) return 1 ;; esac
  done
}

# ----------------------------------------------------------------------------- menus (same UX as make-offline-zip.sh; scrolling window)
USE_ARROWS=0
if [ "$INTERACTIVE" = "1" ] && [ -t 2 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != "dumb" ]; then USE_ARROWS=1; fi
TERM_ROWS=24; TERM_COLS=80
if [ "$USE_ARROWS" = "1" ]; then
  tsz="$(stty size 2>/dev/null)" || tsz=""
  case "$tsz" in [0-9]*" "[0-9]*) TERM_ROWS="${tsz% *}"; TERM_COLS="${tsz#* }" ;; esac
  [ "$TERM_ROWS" -gt 0 ] 2>/dev/null || TERM_ROWS=24
  [ "$TERM_COLS" -gt 20 ] 2>/dev/null || TERM_COLS=80
fi

MENU_KEY=""
menu_read_key() { # Sets MENU_KEY: up | down | space | enter | all | none | eof | other
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

menu_draw() { # $1 = 1 on the first draw
  local i mark plain end
  [ "$1" = "1" ] || printf '\033[%dA' "$MENU_LINES" >&2
  if [ "$MENU_CUR" -lt "$MENU_TOP" ]; then MENU_TOP="$MENU_CUR"; fi
  if [ "$MENU_CUR" -ge $((MENU_TOP + MENU_VIS)) ]; then MENU_TOP=$((MENU_CUR - MENU_VIS + 1)); fi
  printf '\r\033[K%s\n' "$MENU_TITLE" >&2
  if [ -n "$MENU_HEADER" ]; then printf '\r\033[K%s\n' "${MENU_HEADER:0:$((TERM_COLS - 1))}" >&2; fi
  i="$MENU_TOP"; end=$((MENU_TOP + MENU_VIS))
  while [ "$i" -lt "$end" ]; do
    mark="[ ]"; [ "${MI_ON[$i]}" = "1" ] && mark="[x]"
    plain="$(printf '%s %s %-*s  %s' "$([ "$i" = "$MENU_CUR" ] && echo '>' || echo ' ')" "$mark" "$MENU_LABEL_W" "${MI_LABEL[$i]}" "${MI_DESC[$i]}")"
    plain="  ${plain:0:$((TERM_COLS - 3))}"
    if [ "$i" = "$MENU_CUR" ]; then printf '\r\033[K\033[7m%s\033[0m\n' "$plain" >&2; else printf '\r\033[K%s\n' "$plain" >&2; fi
    i=$((i + 1))
  done
  plain="$MENU_FOOTER"
  if [ "$MENU_N" -gt "$MENU_VIS" ]; then plain="$plain  ($((MENU_TOP + 1))-$end of $MENU_N)"; fi
  printf '\r\033[K%s\n' "${plain:0:$((TERM_COLS - 1))}" >&2
}

# Checkbox menu: items in MI_LABEL / MI_DESC / MI_ON; $1 title, $2 header line (may be empty), $3 initial row, $4 footer.
arrow_menu() {
  local i
  MENU_TITLE="$1"; MENU_HEADER="$2"; MENU_CUR="$3"; MENU_FOOTER="$4"; MENU_N="${#MI_LABEL[@]}"; MENU_TOP=0
  MENU_LABEL_W=8
  for i in "${MI_LABEL[@]}"; do [ "${#i}" -le "$MENU_LABEL_W" ] || MENU_LABEL_W="${#i}"; done
  [ "$MENU_LABEL_W" -le 46 ] || MENU_LABEL_W=46
  MENU_VIS="$MENU_N"
  i=$((TERM_ROWS - 5)); [ -n "$MENU_HEADER" ] && i=$((i - 1))
  [ "$i" -ge 3 ] || i=3
  [ "$MENU_VIS" -le "$i" ] || MENU_VIS="$i"
  MENU_LINES=$((MENU_VIS + 2)); [ -n "$MENU_HEADER" ] && MENU_LINES=$((MENU_LINES + 1))
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
      space) if [ "${MI_ON[MENU_CUR]}" = "1" ]; then MI_ON[MENU_CUR]=0; else MI_ON[MENU_CUR]=1; fi ;;
      all) i=0; while [ "$i" -lt "$MENU_N" ]; do MI_ON[i]=1; i=$((i + 1)); done ;;
      none) i=0; while [ "$i" -lt "$MENU_N" ]; do MI_ON[i]=0; i=$((i + 1)); done ;;
      enter) break ;;
      eof) menu_restore; trap - INT TERM HUP; trap cleanup_work EXIT; die "Input closed while a menu was open." ;;
    esac
    menu_draw 0
  done
  menu_restore
  trap - INT TERM HUP
  trap cleanup_work EXIT
}

# ----------------------------------------------------------------------------- history
last_action() { # $1 bundle -> "<action> <iso time>" of its newest history line (empty when none)
  [ -f "$HISTORY" ] || return 0
  awk -F'\t' -v b="$1" '$2 == b { a = $3; t = $1 } END { if (a != "") print a " " t }' "$HISTORY"
}
history_add() { # $1 bundle, $2 action, $3 services, $4 note
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" "$2" "$3" "${4:-}" >> "$HISTORY"
}
is_applied() { case "$(last_action "$1")" in applied*) return 0 ;; *) return 1 ;; esac; }

# ----------------------------------------------------------------------------- compose helpers
# Compose files that can hold images of a bundle (add-on services such as gotenberg/tileserver live in docker-compose.yml).
COMPOSE_FILES="$INSTALL_DIR/docker-compose.yml"
for f in vision/docker-compose.yml vision/docker-compose.gpu.yml ollama/docker-compose.yml vllm/docker-compose.yml speaches/compose.cpu.yaml; do
  [ -f "$INSTALL_DIR/$f" ] && COMPOSE_FILES="$COMPOSE_FILES $INSTALL_DIR/$f"
done

compose_services_for_ref() { # $1 compose file, $2 image ref -> names of the services that use this image
  awk -v want="$2" '
    /^[^ #]/ { svc = "" }
    /^  [A-Za-z0-9_.-]+:[ \t]*$/ { svc = $1; sub(/:$/, "", svc); next }
    svc != "" && /^    image:/ {
      v = $0; sub(/^    image:[ \t]*/, "", v); gsub(/["\047]/, "", v); sub(/[ \t]*#.*$/, "", v); sub(/[ \t]+$/, "", v)
      while (match(v, /\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]*\}/)) {
        inner = substr(v, RSTART + 2, RLENGTH - 3); sub(/^[^:]*:-/, "", inner)
        v = substr(v, 1, RSTART - 1) inner substr(v, RSTART + RLENGTH)
      }
      if (v == want) print svc
    }
  ' "$1"
}

# Runs docker compose for one compose file in its own directory: dcx <compose file> <args...>
dcx() {
  local f="$1" d b
  shift
  d="$(dirname "$f")"; b="$(basename "$f")"
  if [ -f "$INSTALL_DIR/settings.json" ]; then METEOR_SETTINGS="$(cat "$INSTALL_DIR/settings.json")"; export METEOR_SETTINGS; fi
  if [ "$f" = "$INSTALL_DIR/docker-compose.yml" ]; then ( cd "$d" && $DC "$@" )
  else ( cd "$d" && $DC -f "$b" "$@" ); fi
}
svc_running_ids() { dcx "$1" ps -q "$2" 2>/dev/null | sed '/^$/d' || true; }
svc_all_ids() { dcx "$1" ps -aq "$2" 2>/dev/null | sed '/^$/d' || true; }
container_image_id() { docker inspect -f '{{.Image}}' "$1" 2>/dev/null || true; }

# Waits until container $1 is running (and healthy when it has a health check), then keeps watching it for $2 seconds.
wait_container_ready() { # returns 0 when ready and stable
  local cid="$1" stable="$2" t=0 st restarting health rc0 rc1 line
  while [ "$t" -lt "$READY_TIMEOUT" ]; do
    line="$(docker inspect -f '{{.State.Status}}|{{.State.Restarting}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.RestartCount}}' "$cid" 2>/dev/null)" || return 1
    st="${line%%|*}"; line="${line#*|}"; restarting="${line%%|*}"; line="${line#*|}"; health="${line%%|*}"; rc0="${line#*|}"
    case "$st" in exited|dead) err "Container $(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null) stopped (status: $st)."; return 1 ;; esac
    if [ "$health" = "unhealthy" ]; then err "Container $(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null) is unhealthy."; return 1; fi
    if [ "$st" = "running" ] && [ "$restarting" = "false" ] && { [ "$health" = "none" ] || [ "$health" = "healthy" ]; }; then break; fi
    sleep 2; t=$((t + 2))
  done
  [ "$t" -lt "$READY_TIMEOUT" ] || { err "Timed out after ${READY_TIMEOUT}s waiting for $(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null) to become ready."; return 1; }
  sleep "$stable"
  line="$(docker inspect -f '{{.State.Status}}|{{.State.Restarting}}|{{.RestartCount}}' "$cid" 2>/dev/null)" || return 1
  rc1="${line##*|}"; st="${line%%|*}"
  if [ "$st" != "running" ] || [ "$rc1" != "$rc0" ]; then
    err "Container $(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null) is not stable (status: $st, restarts: $rc0 -> $rc1)."
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------------- 2. find the update bundles
step "2. Looking for update bundles"
B_N=0
B_NAME=(); B_DIR=(); B_STEM=(); B_DATE=(); B_SVCS=(); B_BYTES=(); B_ARCH=(); B_CFG=(); B_BASE=()
scan_bundles() { # $1 directory
  local d="$1" m stem name kind
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    kind="$(json_str "$m" bundle_kind)"
    [ "$kind" = "update" ] || continue
    stem="$(basename "$m" .MANIFEST.json)"
    name="$(json_str "$m" bundle_name)"
    if [ "$name" != "$stem" ]; then warn "Ignoring $m: its bundle_name ('$name') does not match the file name."; continue; fi
    B_NAME[B_N]="$name"; B_DIR[B_N]="$(dirname "$m")"; B_STEM[B_N]="$stem"
    B_DATE[B_N]="$(json_str "$m" created_at)"
    B_SVCS[B_N]="$(sed -n 's/^  "services": \[\(.*\)\],\{0,1\}$/\1/p' "$m" | tr -d '"' | sed 's/, */,/g' | head -1)"
    B_BYTES[B_N]="$(json_str "$m" images_bytes)"
    B_ARCH[B_N]="$(json_str "$m" target_arch)"
    B_CFG[B_N]="$(json_str "$m" with_compose)"
    B_BASE[B_N]="$(json_str "$m" base_bundle)"
    B_N=$((B_N + 1))
  done < <(find "$d" -maxdepth 2 -name '*.MANIFEST.json' -type f 2>/dev/null | sort)
}
if [ -n "$SRC_DIR" ]; then
  [ -d "$SRC_DIR" ] || die "--dir: not a directory: $SRC_DIR"
  SRC_DIR="$(cd "$SRC_DIR" && pwd)"
  scan_bundles "$SRC_DIR"
else
  scan_bundles "$PWD"
  SRC_DIR="$PWD"
  if [ "$B_N" -eq 0 ] && [ "$SCRIPT_DIR" != "$PWD" ]; then scan_bundles "$SCRIPT_DIR"; SRC_DIR="$SCRIPT_DIR"; fi
fi

# sort by creation time (the name carries the date, so the text sort of created_at is chronological)
if [ "$B_N" -gt 1 ]; then
  ORDER="$(i=0; while [ "$i" -lt "$B_N" ]; do printf '%s\t%s\n' "${B_DATE[$i]}" "$i"; i=$((i + 1)); done | sort | cut -f2)"
  S_NAME=("${B_NAME[@]}"); S_DIR=("${B_DIR[@]}"); S_STEM=("${B_STEM[@]}"); S_DATE=("${B_DATE[@]}"); S_SVCS=("${B_SVCS[@]}")
  S_BYTES=("${B_BYTES[@]}"); S_ARCH=("${B_ARCH[@]}"); S_CFG=("${B_CFG[@]}"); S_BASE=("${B_BASE[@]}")
  n=0
  for i in $ORDER; do
    B_NAME[n]="${S_NAME[$i]}"; B_DIR[n]="${S_DIR[$i]}"; B_STEM[n]="${S_STEM[$i]}"; B_DATE[n]="${S_DATE[$i]}"; B_SVCS[n]="${S_SVCS[$i]}"
    B_BYTES[n]="${S_BYTES[$i]}"; B_ARCH[n]="${S_ARCH[$i]}"; B_CFG[n]="${S_CFG[$i]}"; B_BASE[n]="${S_BASE[$i]}"
    n=$((n + 1))
  done
fi

bundle_status() { # $1 index -> short status text
  local la
  la="$(last_action "${B_NAME[$1]}")"
  case "$la" in
    applied*) la="${la#applied }"; printf 'applied %s' "${la:0:10}" ;;
    rolled-back*) printf 'rolled back' ;;
    failed*) printf 'last run failed' ;;
    *) printf 'new' ;;
  esac
}
bundle_line() { # $1 index
  local arch_note=""
  [ "${B_ARCH[$1]}" = "$HOST_ARCH" ] || arch_note=" | ARCH ${B_ARCH[$1]} (server: $HOST_ARCH)"
  printf '%s | %s | %s | %s%s%s' "${B_DATE[$1]%Z}" "${B_SVCS[$1]}" "$(human_size "${B_BYTES[$1]:-0}")" "$(bundle_status "$1")" \
    "$([ "${B_CFG[$1]}" = "true" ] && echo ' | +config')" "$arch_note"
}

if [ "$ROLLBACK_MODE" = "0" ]; then
  [ "$B_N" -gt 0 ] || die "No update bundle found in $SRC_DIR (looked for *.MANIFEST.json of update bundles). Copy ALL files of the bundle into one directory or use --dir."
  ok "Found $B_N update bundle(s) in $SRC_DIR:"
  i=0
  while [ "$i" -lt "$B_N" ]; do printf '  %s\n      %s\n' "${B_NAME[$i]}" "$(bundle_line "$i")"; i=$((i + 1)); done
  [ "$LIST_ONLY" = "0" ] || exit 0
fi

# ----------------------------------------------------------------------------- rollback
WORK=""
cleanup_work() {
  if [ "$KEEP_WORK" = "0" ] && [ -n "$WORK" ] && [ -d "$WORK" ]; then rm -rf "$WORK"; fi
}
trap cleanup_work EXIT

svc_rank() { # apply order: data stores first, the web application next, the proxy last
  case "$1" in mongo|redis|qdrant|mail) echo 0 ;; webapp) echo 2 ;; sclab-proxy) echo 3 ;; *) echo 1 ;; esac
}

refresh_proxy() { # nginx resolves the upstream at start-up: restart it after webapp was replaced (as update.sh does)
  local f="$INSTALL_DIR/docker-compose.yml" ids
  ids="$(svc_all_ids "$f" sclab-proxy)"
  [ -n "$ids" ] || return 0
  info "Restarting sclab-proxy so that it picks up the new webapp container"
  dcx "$f" stop sclab-proxy >/dev/null 2>&1 || true
  dcx "$f" up -d --no-deps sclab-proxy
}

# Rolling update of webapp (same idea as update.sh): start the new container next to the old one, wait, stop the old one.
apply_webapp_rolling() { # $1 compose file
  local f="$1" prev n id after new="" nid
  prev="$(svc_running_ids "$f" webapp)"
  n="$(printf '%s\n' "$prev" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$n" -eq 0 ]; then
    info "webapp is not running: starting it"
    dcx "$f" up -d --no-deps webapp
    for id in $(svc_running_ids "$f" webapp); do wait_container_ready "$id" "$STABLE_SECS" || return 1; done
    return 0
  fi
  info "webapp rolling update: starting $n new container(s) next to the running one(s)"
  dcx "$f" up -d --no-deps --scale "webapp=$((n * 2))" --no-recreate webapp
  after="$(svc_running_ids "$f" webapp)"
  for id in $after; do
    case " ${prev//$'\n'/ } " in *" $id "*) ;; *) new="$new $id" ;; esac
  done
  if [ -z "$new" ]; then err "No new webapp container was started."; return 1; fi
  info "Waiting for the new webapp container(s) (at least ${WAIT_SECS}s)"
  for nid in $new; do
    if ! wait_container_ready "$nid" "$WAIT_SECS"; then
      err "The new webapp container failed its health check. The previous container keeps running; removing the new one."
      docker logs --tail 30 "$nid" 2>&1 | sed 's/^/    | /' >&2 || true
      for id in $new; do docker rm -f "$id" >/dev/null 2>&1 || true; done
      return 1
    fi
  done
  mkdir -p "$INSTALL_DIR/data/logs"
  dcx "$f" logs > "$INSTALL_DIR/data/logs/sclab-compose-logs-$(date +%F_%H%M).log" 2>&1 || true
  info "Stopping the previous webapp container(s)"
  for id in $prev; do
    docker stop -t 30 "$id" >/dev/null 2>&1 || true
    docker rm -f "$id" >/dev/null 2>&1 || true
  done
  dcx "$f" up -d --no-deps --scale "webapp=$n" --no-recreate webapp
  return 0
}

# Brings one service to the image its tag points to now. $1 compose file, $2 service, $3 expected image id (may be empty)
apply_service() {
  local f="$1" svc="$2" want="$3" id cur_ok=1 ids
  ids="$(svc_running_ids "$f" "$svc")"
  if [ -n "$want" ] && [ -n "$ids" ]; then
    for id in $ids; do [ "$(container_image_id "$id")" = "$want" ] || cur_ok=0; done
    if [ "$cur_ok" = "1" ]; then ok "$svc already runs the expected image"; return 0; fi
  fi
  if [ "$svc" = "webapp" ] && [ "$f" = "$INSTALL_DIR/docker-compose.yml" ]; then
    apply_webapp_rolling "$f" || return 1
    if [ "${PROXY_IN_PLAN:-0}" = "0" ]; then refresh_proxy || return 1; fi
  else
    info "docker compose up -d --no-deps $svc"
    dcx "$f" up -d --no-deps "$svc" || return 1
    ids="$(svc_running_ids "$f" "$svc")"
    [ -n "$ids" ] || { err "$svc is not running after the update."; return 1; }
    for id in $ids; do wait_container_ready "$id" "$STABLE_SECS" || { docker logs --tail 30 "$id" 2>&1 | sed 's/^/    | /' >&2 || true; return 1; }; done
  fi
  if [ -n "$want" ]; then
    for id in $(svc_running_ids "$f" "$svc"); do
      [ "$(container_image_id "$id")" = "$want" ] || { err "$svc runs an unexpected image ($(short_id "$(container_image_id "$id")") instead of $(short_id "$want"))."; return 1; }
    done
  fi
  ok "$svc is up to date and healthy"
}

# Restores the image tags and config files recorded for bundle $1 and re-applies the services. Used by --rollback and after a failure.
do_rollback() { # $1 bundle name
  local name="$1" rec="$STATE_DIR/$1" ref old rb file svc state fl rank
  [ -f "$rec/rollback.tsv" ] || die "No rollback record for '$name' ($rec/rollback.tsv)."
  step "Rolling back $name"
  while IFS='|' read -r ref old rb _newid _file _svc _state; do
    [ -n "$old" ] || continue
    if [ -n "$rb" ] && docker image inspect "$rb" >/dev/null 2>&1; then docker tag "$rb" "$ref"
    elif docker image inspect "$old" >/dev/null 2>&1; then docker tag "$old" "$ref"
    else err "The previous image of $ref ($(short_id "$old")) is no longer on this server."; continue; fi
    ok "$ref -> previous image $(short_id "$old")"
  done < "$rec/rollback.tsv" | sort -u
  # config files: put the backups back, remove the files the update added
  if [ -d "$rec/config-backup" ]; then
    ( cd "$rec/config-backup" && find . -type f | sed 's#^\./##' ) | while IFS= read -r fl; do
      mkdir -p "$(dirname "$INSTALL_DIR/$fl")"; cp -p "$rec/config-backup/$fl" "$INSTALL_DIR/$fl"; info "Restored $fl"
    done
  fi
  if [ -f "$rec/config-added.list" ]; then
    while IFS= read -r fl; do [ -n "$fl" ] && rm -f "$INSTALL_DIR/$fl" && info "Removed $fl (added by the update)"; done < "$rec/config-added.list"
  fi
  PROXY_IN_PLAN=0
  if grep -q '|sclab-proxy|update$' "$rec/rollback.tsv" 2>/dev/null; then PROXY_IN_PLAN=1; fi
  local failed=0
  for rank in 0 1 2 3; do
    while IFS='|' read -r _ref old _rb _newid file svc state; do
      [ "$state" = "update" ] && [ "$(svc_rank "$svc")" = "$rank" ] || continue
      [ -n "$old" ] || continue
      apply_service "$file" "$svc" "$old" || { err "Could not restore $svc to the previous image."; failed=1; }
    done < "$rec/rollback.tsv"
  done
  if [ "$failed" = "1" ]; then
    history_add "$name" "rollback-failed" "" "see the messages above"
    die "The rollback did not finish cleanly. Check: cd $INSTALL_DIR && docker compose ps && docker compose logs"
  fi
  history_add "$name" "rolled-back" "" ""
  ok "Rollback of $name finished."
}

if [ "$ROLLBACK_MODE" = "1" ]; then
  if [ -z "$ROLLBACK_NAME" ]; then
    ROLLBACK_NAME="$([ -f "$HISTORY" ] && awk -F'\t' '$3 == "applied" { o[$2] = NR } $3 == "rolled-back" { delete o[$2] } END { m = 0; for (b in o) if (o[b] > m) { m = o[b]; r = b } print r }' "$HISTORY")"
    [ -n "$ROLLBACK_NAME" ] || die "Nothing to roll back: no applied update bundle in $HISTORY."
  fi
  [ -d "$STATE_DIR/$ROLLBACK_NAME" ] || die "No rollback record for '$ROLLBACK_NAME' in $STATE_DIR."
  step "Rollback"
  info "Update bundle to roll back: $ROLLBACK_NAME ($(last_action "$ROLLBACK_NAME"))"
  newer="$(awk -F'\t' -v b="$ROLLBACK_NAME" 'f && $3 == "applied" && $2 != b { print $2 } $2 == b && $3 == "applied" { f = 1 }' "$HISTORY" 2>/dev/null | sort -u | tr '\n' ' ')"
  if [ -n "$newer" ]; then warn "Newer update bundle(s) were applied after it: $newer - their changes are undone as well for the images they share."; fi
  ask_yn "Restore the previous images and services now?" Y || die "Cancelled."
  [ "$DRY_RUN" = "0" ] || { info "--dry-run: nothing changed."; exit 0; }
  do_rollback "$ROLLBACK_NAME"
  exit 0
fi

# ----------------------------------------------------------------------------- choose the bundle(s)
step "3. Choosing the bundle"
CHOSEN=""   # indexes in date order
sort_idx() { tr ' ' '\n' | sed '/^$/d' | sort -n | uniq | tr '\n' ' '; }
bundle_index() { # $1 name -> index (empty when unknown)
  local i=0
  while [ "$i" -lt "$B_N" ]; do [ "${B_NAME[$i]}" = "$1" ] && { echo "$i"; return 0; }; i=$((i + 1)); done
  return 0
}
if [ -n "${BUNDLE_ARGS# }" ]; then
  for b in $BUNDLE_ARGS; do
    idx="$(bundle_index "${b%.MANIFEST.json}")"
    [ -n "$idx" ] || die "Update bundle '$b' not found in $SRC_DIR. (--list shows what is there)"
    CHOSEN="$CHOSEN $idx"
  done
  CHOSEN="$(printf '%s' "$CHOSEN" | sort_idx)"
elif [ "$APPLY_ALL" = "1" ]; then
  i=0
  while [ "$i" -lt "$B_N" ]; do
    if is_applied "${B_NAME[$i]}" && [ "$FORCE" = "0" ]; then info "Skipping ${B_NAME[$i]} (already applied: $(last_action "${B_NAME[$i]}"))"; else CHOSEN="$CHOSEN $i"; fi
    i=$((i + 1))
  done
elif [ "$B_N" -eq 1 ]; then
  CHOSEN="0"
  info "One update bundle found: ${B_NAME[0]}"
elif [ "$INTERACTIVE" = "0" ]; then
  die "Several update bundles found and no terminal: choose with --bundle NAME (or --all). Found: ${B_NAME[*]}"
elif [ "$USE_ARROWS" = "1" ]; then
  MI_LABEL=(); MI_DESC=(); MI_ON=()
  i=0
  while [ "$i" -lt "$B_N" ]; do MI_LABEL+=("${B_NAME[$i]}"); MI_DESC+=("$(bundle_line "$i")"); MI_ON+=(0); i=$((i + 1)); done
  # start on the newest bundle that was not applied yet
  start=$((B_N - 1)); i=0
  while [ "$i" -lt "$B_N" ]; do is_applied "${B_NAME[$i]}" || start="$i"; i=$((i + 1)); done
  arrow_menu "Update bundles in $SRC_DIR (oldest first)" "  Enter on one row applies it; check several with Space to apply them in date order" "$start" \
    "  Up/Down (or j/k) move | Space check | a all | n none | Enter confirm"
  i=0
  while [ "$i" -lt "$B_N" ]; do [ "${MI_ON[$i]}" = "1" ] && CHOSEN="$CHOSEN $i"; i=$((i + 1)); done
  [ -n "$CHOSEN" ] || CHOSEN="$MENU_CUR"
else
  printf '\nUpdate bundles in %s (oldest first):\n' "$SRC_DIR"
  i=0
  while [ "$i" -lt "$B_N" ]; do printf '  %d) %s\n       %s\n' "$((i + 1))" "${B_NAME[$i]}" "$(bundle_line "$i")"; i=$((i + 1)); done
  while [ -z "$CHOSEN" ]; do
    printf 'Number(s) to apply, comma separated (applied in date order), a = all [%d]: ' "$B_N"
    IFS= read -r a || a=""
    a="${a:-$B_N}"
    if [ "$a" = "a" ] || [ "$a" = "A" ]; then i=0; while [ "$i" -lt "$B_N" ]; do CHOSEN="$CHOSEN $i"; i=$((i + 1)); done; break; fi
    for tok in $(echo "$a" | tr ',' ' '); do
      case "$tok" in ''|*[!0-9]*) echo "Ignoring '$tok'." ;; *) if [ "$tok" -ge 1 ] && [ "$tok" -le "$B_N" ]; then CHOSEN="$CHOSEN $((tok - 1))"; else echo "No such number: $tok"; fi ;; esac
    done
  done
  CHOSEN="$(printf '%s' "$CHOSEN" | sort_idx)"
fi
[ -n "${CHOSEN// /}" ] || { info "Nothing to apply."; exit 0; }
CHOSEN="$(printf '%s' "$CHOSEN" | sort_idx)"
info "Bundle(s) to apply, in this order:"
for i in $CHOSEN; do printf '  - %s\n' "${B_NAME[$i]}"; done

# ----------------------------------------------------------------------------- per-bundle processing
verify_checksums() { # $1 dir, $2 stem
  local d="$1" stem="$2" sums parts p missing=""
  sums="$d/$stem.SHA256SUMS"
  [ -f "$sums" ] || die "$sums not found. Copy ALL files of the bundle into one directory."
  parts="$(awk '{print $2}' "$sums" | sed 's/^\*//' | grep -E '\.tar\.gz(\.part[0-9]+)?$' || true)"
  [ -n "$parts" ] || die "No bundle archive (*.tar.gz or *.tar.gz.part*) is listed in $stem.SHA256SUMS."
  for p in $parts; do [ -f "$d/$p" ] || missing="$missing $p"; done
  [ -z "$missing" ] || die "Missing bundle file(s):$missing - copy every part next to $stem.SHA256SUMS."
  info "Verifying SHA256 checksums of $(echo "$parts" | wc -l | tr -d ' ') part(s) - this can take a while for big bundles"
  if ! ( cd "$d" && $SHA_CHECK "$stem.SHA256SUMS" >/dev/null ); then
    ( cd "$d" && $SHA_CHECK "$stem.SHA256SUMS" 2>&1 | grep FAILED | sed 's/^/    /' ) >&2 || true
    die "Checksum verification FAILED for $stem. A file is damaged or incomplete - copy it to the server again. Nothing was changed."
  fi
  ok "All checksums match"
  PARTS="$parts"
}

restore_old_tags() { # puts the tags back to the images recorded in $WORK/old.psv (used when the update is not applied)
  local ref old
  [ -f "$WORK/old.psv" ] || return 0
  while IFS='|' read -r ref old; do
    [ -n "$old" ] || continue
    docker image inspect "$old" >/dev/null 2>&1 && docker tag "$old" "$ref" 2>/dev/null || true
  done < "$WORK/old.psv"
}

# ---- config snapshot (bundles built with --with-compose)
is_protected() { # files that are never overwritten: settings, env files, certificates, data, installer state
  case "$1" in
    settings.json|*.env|cert/*|jwt/*|data/*|.init|.offline|"$HIST_DIRNAME"/*|vision/data/*) return 0 ;;
    *) return 1 ;;
  esac
}
find_base_file() { # $1 relative path -> prints the pristine copy this file was installed from (newest snapshot, else the install bundle)
  local c
  if [ -f "$STATE_DIR/snapshots.list" ]; then
    while IFS= read -r c; do
      [ -f "$STATE_DIR/snapshots/$c/$1" ] && { printf '%s' "$STATE_DIR/snapshots/$c/$1"; return 0; }
    done < <(sed '1!G;h;$!d' "$STATE_DIR/snapshots.list")   # newest first
  fi
  for c in "$INSTALL_DIR"/../bundle-*/repo; do
    [ -f "$c/$1" ] && { printf '%s' "$c/$1"; return 0; }
  done
  return 0
}

CFG_PLAN="" # lines: action|relative path|base file
TRIM_FAILED=0
# The installed docker-compose.yml only holds the services chosen at install time (service-manage.sh removed the others,
# also from depends_on). Apply the same trimming to the bundled copy so that the merge does not bring them back.
COMPOSE_DEFAULT_SVCS="qdrant ai-service node-vm-service sclab-agent gis-process mqtt-client mqtt-broker kafka-client"
trim_snapshot() { # $1 extracted repo dir
  local repo="$1" svc drop=""
  TRIM_FAILED=0
  [ -f "$repo/docker-compose.yml" ] && [ -f "$repo/service-manage.sh" ] || return 0
  for svc in $COMPOSE_DEFAULT_SVCS; do
    if grep -Eq "^  $svc:[[:space:]]*$" "$repo/docker-compose.yml" && ! grep -Eq "^  $svc:[[:space:]]*$" "$INSTALL_DIR/docker-compose.yml"; then drop="$drop $svc"; fi
  done
  [ -n "$drop" ] || return 0
  # shellcheck disable=SC2086
  if ( cd "$repo" && SERVICE_MANAGE_QUIET=1 bash ./service-manage.sh disable $drop >/dev/null 2>&1 ); then
    info "Bundled docker-compose.yml trimmed to the installed services (removed:$drop)"
  else
    warn "Could not trim the bundled docker-compose.yml to the installed services: it will not be merged automatically."
    TRIM_FAILED=1
  fi
}
plan_config() { # $1 extracted repo dir; fills CFG_PLAN and prints the summary / diffs
  local repo="$1" rel inst base act
  CFG_PLAN=""
  while IFS= read -r rel; do
    inst="$INSTALL_DIR/$rel"
    if [ -e "$inst" ] && cmp -s "$repo/$rel" "$inst"; then continue; fi
    base="$(find_base_file "$rel")"
    # the bundle's copy is the same as the pristine file this installation started from: nothing new upstream
    if [ -n "$base" ] && [ -e "$inst" ] && cmp -s "$base" "$repo/$rel"; then continue; fi
    if is_protected "$rel"; then
      if [ -e "$inst" ]; then
        printf '  protected  %s (installed copy differs from the bundle: kept; the bundle copy is saved in %s/snapshots)\n' "$rel" "$HIST_DIRNAME"
      else
        CFG_PLAN="$CFG_PLAN$(printf 'add|%s|\n' "$rel")"$'\n'
        printf '  new        %s (protected type: only created, never overwritten)\n' "$rel"
      fi
      continue
    fi
    if [ ! -e "$inst" ]; then
      CFG_PLAN="$CFG_PLAN$(printf 'add|%s|\n' "$rel")"$'\n'
      printf '  new        %s\n' "$rel"; continue
    fi
    if [ "$rel" = "docker-compose.yml" ] && [ "$TRIM_FAILED" = "1" ]; then act=conflict
    elif [ -n "$base" ] && cmp -s "$base" "$inst"; then act=replace
    elif [ -n "$base" ] && command_exists git; then
      cp "$inst" "$WORK/merge.tmp"
      if git merge-file -q "$WORK/merge.tmp" "$base" "$repo/$rel" 2>/dev/null; then act=merge; else act=conflict; fi
    else act=conflict; fi
    CFG_PLAN="$CFG_PLAN$(printf '%s|%s|%s\n' "$act" "$rel" "$base")"$'\n'
    case "$act" in
      replace) printf '  replace    %s (you did not change it locally)\n' "$rel" ;;
      merge) printf '  merge      %s (your local changes are kept, the new lines are merged in)\n' "$rel" ;;
      conflict) printf '  CONFLICT   %s (changed locally and in the bundle: yours is kept, the new version is written to %s.upstream)\n' "$rel" "$rel" ;;
    esac
  done < <(cd "$repo" && find . -type f | sed 's#^\./##' | grep -v '\.DS_Store$' | sort)
}
show_config_diffs() { # $1 repo dir
  local repo="$1" act rel base shown=0
  while IFS='|' read -r act rel base; do
    [ -n "$act" ] || continue
    echo "----- $rel ($act)"
    case "$act" in
      add) echo "  (new file, $(wc -l < "$repo/$rel" | tr -d ' ') lines)" ;;
      replace|conflict) diff -u "$INSTALL_DIR/$rel" "$repo/$rel" 2>/dev/null | head -n 80 || true ;;
      merge)
        cp "$INSTALL_DIR/$rel" "$WORK/merge.tmp"; git merge-file -q "$WORK/merge.tmp" "$base" "$repo/$rel" 2>/dev/null || true
        diff -u "$INSTALL_DIR/$rel" "$WORK/merge.tmp" 2>/dev/null | head -n 80 || true ;;
    esac
    shown=$((shown + 1))
  done <<EOF
$CFG_PLAN
EOF
  [ "$shown" -gt 0 ] || echo "  (no file changes)"
}
apply_config() { # $1 repo dir, $2 bundle name; backs up what it overwrites
  local repo="$1" name="$2" rec="$STATE_DIR/$2" act rel base
  mkdir -p "$rec/config-backup"
  : > "$rec/config-added.list"
  while IFS='|' read -r act rel base; do
    [ -n "$act" ] || continue
    mkdir -p "$(dirname "$INSTALL_DIR/$rel")"
    case "$act" in
      add) printf '%s\n' "$rel" >> "$rec/config-added.list"; cp -p "$repo/$rel" "$INSTALL_DIR/$rel" ;;
      replace)
        mkdir -p "$(dirname "$rec/config-backup/$rel")"; cp -p "$INSTALL_DIR/$rel" "$rec/config-backup/$rel"
        cat "$repo/$rel" > "$INSTALL_DIR/$rel"; [ ! -x "$repo/$rel" ] || chmod +x "$INSTALL_DIR/$rel" ;;
      merge)
        mkdir -p "$(dirname "$rec/config-backup/$rel")"; cp -p "$INSTALL_DIR/$rel" "$rec/config-backup/$rel"
        cp "$INSTALL_DIR/$rel" "$WORK/merge.tmp"; git merge-file -q "$WORK/merge.tmp" "$base" "$repo/$rel" 2>/dev/null || true
        cat "$WORK/merge.tmp" > "$INSTALL_DIR/$rel" ;;
      conflict) cp "$repo/$rel" "$INSTALL_DIR/$rel.upstream" ;;
    esac
  done <<EOF
$CFG_PLAN
EOF
  rm -rf "${STATE_DIR:?}/snapshots/$name"; mkdir -p "$STATE_DIR/snapshots/$name"
  ( cd "$repo" && tar -cf - . ) | ( cd "$STATE_DIR/snapshots/$name" && tar -xf - )
  printf '%s\n' "$name" >> "$STATE_DIR/snapshots.list"
  ok "Config files merged (backup: $rec/config-backup)"
}

process_bundle() { # $1 index
  local bi="$1" name dir stem arch want_platform_arch
  RB_STAMP="$(date +%Y%m%d-%H%M%S)-$bi"   # one rollback tag per bundle, even when several are applied in one run
  name="${B_NAME[$bi]}"; dir="${B_DIR[$bi]}"; stem="${B_STEM[$bi]}"; arch="${B_ARCH[$bi]}"
  local manifest="$dir/$stem.MANIFEST.json"
  step "Bundle $name"
  [ "$arch" = "$HOST_ARCH" ] || die "Architecture mismatch: this server is '$HOST_ARCH' but bundle '$name' was built for '$arch'. Build a matching update bundle with make-offline-update-zip.sh --arch $HOST_ARCH."
  want_platform_arch="$HOST_DOCKER_ARCH"
  ok "Architecture: $arch (matches this server)"

  # duplicate check
  local la
  la="$(last_action "$name")"
  case "$la" in
    applied*)
      warn "Bundle $name was already applied (${la#applied })."
      if [ "$FORCE" = "1" ]; then info "--force: applying it again."
      elif [ "$ASSUME_YES" = "1" ]; then info "Skipping it (use --force to apply again)."; return 0
      else ask_yn "Apply it again?" N || { info "Skipped."; return 0; }; fi ;;
  esac
  if [ -n "${B_BASE[$bi]}" ]; then
    if ls -d "$INSTALL_DIR"/../bundle-"${B_BASE[$bi]}" >/dev/null 2>&1; then ok "Base bundle ${B_BASE[$bi]} is the one this installation was made from."
    else warn "This update is meant for the base bundle '${B_BASE[$bi]}', which is not found next to $INSTALL_DIR (a different or manually installed base?)."; fi
  fi

  verify_checksums "$dir" "$stem"

  # image list from the (verified) manifest: ref|id|file|digest|size|services|created
  PLAN_IMG="$(sed -n 's/^ *{"ref": "\([^"]*\)", "id": "\([^"]*\)", "repo_digest": "\([^"]*\)", "created": "\([^"]*\)", "size_bytes": \([0-9]*\), "services": "\([^"]*\)", "file": "images\/\([^"]*\)"}.*$/\1|\2|\7|\3|\5|\6|\4/p' "$manifest")"
  [ -n "$PLAN_IMG" ] || die "MANIFEST.json of $name lists no images (damaged?)."
  local images_bytes
  images_bytes="$(json_str "$manifest" images_bytes)"; images_bytes="${images_bytes:-0}"

  # disk space
  local base parts_bytes=0 p sz need_kb have_kb droot
  base="${WORK_BASE:-$dir}"
  mkdir -p "$base"
  WORK="$(mktemp -d "$base/.sclab-update-work.XXXXXX")" || die "Cannot create a work directory in $base (use --work-dir)."
  for p in $PARTS; do sz="$(wc -c < "$dir/$p" | tr -d ' ')"; parts_bytes=$((parts_bytes + sz)); done
  need_kb=$(( parts_bytes * 11 / 10 / 1024 + 262144 ))
  have_kb="$(df -Pk "$WORK" | awk 'NR==2 {print $4}')"
  droot="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  [ -n "$droot" ] && [ -d "$droot" ] || { droot="/var/lib/docker"; [ -d "$droot" ] || droot="/var/lib"; }
  if [ "$(df -Pk "$WORK" | awk 'NR==2 {print $1}')" = "$(df -Pk "$droot" | awk 'NR==2 {print $1}')" ]; then need_kb=$((need_kb + images_bytes * 12 / 10 / 1024)); fi
  [ "$have_kb" -ge "$need_kb" ] || die "Not enough free disk space in $base: need about $((need_kb / 1024)) MB, free $((have_kb / 1024)) MB. Use --work-dir on a bigger disk."
  have_kb="$(df -Pk "$droot" | awk 'NR==2 {print $4}')"
  [ "$have_kb" -ge $((images_bytes * 12 / 10 / 1024)) ] || die "Not enough free disk space for the images in $droot: need about $((images_bytes * 12 / 10 / 1048576)) MB, free $((have_kb / 1024)) MB."

  info "Extracting the bundle to $WORK/x"
  mkdir -p "$WORK/x"
  # shellcheck disable=SC2086
  ( cd "$dir" && cat $PARTS ) | tar -xzf - -C "$WORK/x" || die "Extraction failed (archive damaged or disk full)."
  [ -d "$WORK/x/images" ] || die "The bundle contains no images/ directory."

  # what runs now (before anything is loaded): ref|old id
  : > "$WORK/old.psv"
  : > "$WORK/rows.psv"
  local ref nid fname _dg size _svcs _cr cur running f svc ids first_id state have_target
  while IFS='|' read -r ref nid fname _dg size _svcs _cr; do
    cur="$(docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null || true)"
    printf '%s|%s\n' "$ref" "$cur" >> "$WORK/old.psv"
  done <<EOF
$PLAN_IMG
EOF

  # docker load (skipped when the tag already points to the bundled image)
  step "Loading the images of $name"
  local total n=0 loaded_ids=""
  total="$(printf '%s\n' "$PLAN_IMG" | wc -l | tr -d ' ')"
  while IFS='|' read -r ref nid fname _dg size _svcs _cr; do
    n=$((n + 1))
    cur="$(awk -F'|' -v r="$ref" '$1 == r { print $2; exit }' "$WORK/old.psv")"
    if [ -n "$cur" ] && [ "$cur" = "$nid" ]; then ok "[$n/$total] already loaded: $ref"; continue; fi
    [ -f "$WORK/x/images/$fname" ] || { restore_old_tags; die "Image file missing in the bundle: images/$fname"; }
    info "[$n/$total] docker load: $ref ($(human_size "$size"))"
    docker load -i "$WORK/x/images/$fname" >/dev/null || { restore_old_tags; die "docker load failed for $ref"; }
    rm -f "$WORK/x/images/$fname"
    docker image inspect "$ref" >/dev/null 2>&1 || { restore_old_tags; die "After loading, image $ref is not present."; }
    loaded_ids="$loaded_ids $ref"
    if [ "$(docker image inspect -f '{{.Architecture}}' "$ref" 2>/dev/null)" != "$want_platform_arch" ]; then
      restore_old_tags
      die "Architecture mismatch: image $ref is for '$(docker image inspect -f '{{.Architecture}}' "$ref" 2>/dev/null)', but this server is '$HOST_ARCH'. The previous image tags were restored; nothing was changed."
    fi
  done <<EOF
$PLAN_IMG
EOF

  # compare: rows ref|old id|rollback tag|new id|compose file|service|state(update|same|stopped|unused)
  while IFS='|' read -r ref nid fname _dg size _svcs _cr; do
    cur="$(awk -F'|' -v r="$ref" '$1 == r { print $2; exit }' "$WORK/old.psv")"
    nid="$(docker image inspect -f '{{.Id}}' "$ref")"
    have_target=0
    for f in $COMPOSE_FILES; do
      for svc in $(compose_services_for_ref "$f" "$ref"); do
        have_target=1
        running="$(svc_running_ids "$f" "$svc")"
        ids="$(svc_all_ids "$f" "$svc")"
        if [ -n "$running" ]; then
          first_id="$(container_image_id "$(echo "$running" | head -1)")"
          state=same
          for ids in $running; do [ "$(container_image_id "$ids")" = "$nid" ] || state=update; done
          printf '%s|%s||%s|%s|%s|%s\n' "$ref" "$first_id" "$nid" "$f" "$svc" "$state" >> "$WORK/rows.psv"
        elif [ -n "$ids" ]; then
          printf '%s|%s||%s|%s|%s|stopped\n' "$ref" "$cur" "$nid" "$f" "$svc" >> "$WORK/rows.psv"
        else
          printf '%s|%s||%s|%s|%s|unused\n' "$ref" "$cur" "$nid" "$f" "$svc" >> "$WORK/rows.psv"
        fi
      done
    done
    if [ "$have_target" = "0" ]; then printf '%s|%s||%s|-|-|unused\n' "$ref" "$cur" "$nid" >> "$WORK/rows.psv"; fi
  done <<EOF
$PLAN_IMG
EOF

  step "Changes in $name"
  printf '  %-18s %-48s %-13s %-13s %s\n' "SERVICE" "IMAGE" "RUNNING" "NEW" "ACTION"
  local act n_update=0 oldid
  while IFS='|' read -r ref oldid _rb nid f svc state; do
    case "$state" in
      update) act="UPDATE (restart)"; n_update=$((n_update + 1)) ;;
      same) act="unchanged" ;;
      stopped) act="not running: image loaded only" ;;
      *) act="not used by an installed service: image loaded only" ;;
    esac
    [ "$svc" != "webapp" ] || [ "$state" != "update" ] || act="UPDATE (rolling, no downtime)"
    printf '  %-18s %-48s %-13s %-13s %s\n' "$([ "$svc" = "-" ] && echo "(none)" || echo "$svc")" "${ref##*/}" "$([ -n "$oldid" ] && short_id "$oldid" || echo '-')" "$(short_id "$nid")" "$act"
  done < "$WORK/rows.psv"

  # config snapshot
  local cfg_todo=0
  if [ "${B_CFG[$bi]}" = "true" ] && [ "$NO_CONFIG" = "0" ] && [ -d "$WORK/x/repo" ]; then
    step "Config / script files in $name"
    trim_snapshot "$WORK/x/repo"
    plan_config "$WORK/x/repo"
    if [ -n "${CFG_PLAN//[$'\n ']/}" ]; then
      cfg_todo=1
      if ask_yn "Show the differences?" Y; then show_config_diffs "$WORK/x/repo"; fi
    else
      ok "No config file differs from the installed copy."
    fi
  fi

  if [ "$n_update" -eq 0 ] && [ "$cfg_todo" = "0" ] && [ -z "$loaded_ids" ]; then
    ok "Everything in $name is already up to date. Nothing to do."
    restore_old_tags; cleanup_work; WORK=""
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    info "--dry-run: no change was made (the images of $name were loaded; tags were put back)."
    restore_old_tags; cleanup_work; WORK=""
    return 0
  fi
  if ! ask_yn "Apply $name now? ($n_update service(s) will be restarted$([ "$cfg_todo" = "1" ] && echo ", config files will be merged"))" Y; then
    restore_old_tags
    info "Cancelled: the previous image tags were restored; nothing was changed."
    cleanup_work; WORK=""
    return 0
  fi

  # ---- record rollback information BEFORE changing anything
  local rec="$STATE_DIR/$name" repo_of rb
  rm -rf "$rec"; mkdir -p "$rec"
  : > "$rec/rollback.tsv"
  while IFS='|' read -r ref oldid _rb nid f svc state; do
    rb=""
    if [ -n "$oldid" ] && [ "$oldid" != "$nid" ]; then
      repo_of="$(ref_repo "$ref")"
      rb="$repo_of:rollback-$RB_STAMP"
      docker tag "$oldid" "$rb" || { warn "Could not tag the previous image of $ref."; rb=""; }
    fi
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$ref" "$oldid" "$rb" "$nid" "$f" "$svc" "$state" >> "$rec/rollback.tsv"
  done < "$WORK/rows.psv"
  cp "$manifest" "$rec/MANIFEST.json"
  ok "Rollback information saved in $rec (previous images tagged :rollback-$RB_STAMP)"

  if [ "$cfg_todo" = "1" ]; then apply_config "$WORK/x/repo" "$name"; fi

  step "Applying $name"
  PROXY_IN_PLAN=0
  if grep -q '|sclab-proxy|update$' "$WORK/rows.psv"; then PROXY_IN_PLAN=1; fi
  local rank failed="" touched=""
  for rank in 0 1 2 3; do
    while IFS='|' read -r ref oldid _rb nid f svc state; do
      [ "$state" = "update" ] && [ "$(svc_rank "$svc")" = "$rank" ] || continue
      touched="$touched $svc"
      if ! apply_service "$f" "$svc" "$nid"; then failed="$svc"; break; fi
    done < "$WORK/rows.psv"
    [ -z "$failed" ] || break
  done
  # new tags for services that were not running are in place already (their next start uses the new image)

  if [ -n "$failed" ]; then
    err "Updating $failed failed."
    history_add "$name" "failed" "$failed" "health check or start-up failed"
    local do_rb=0
    if [ "$AUTO_ROLLBACK" = "0" ]; then do_rb=0
    elif [ "$ASSUME_YES" = "1" ]; then do_rb=1
    else ask_yn "Roll back to the previous images now?" Y && do_rb=1; fi
    if [ "$do_rb" = "1" ]; then
      cleanup_work; WORK=""
      do_rollback "$name"
      die "Update $name failed and was rolled back."
    fi
    cleanup_work; WORK=""
    die "Update $name failed. To go back to the previous images:  sudo bash $0 --install-dir $INSTALL_DIR --rollback $name"
  fi

  history_add "$name" "applied" "$(echo "$touched" | xargs | tr ' ' ',')" "images: $(printf '%s\n' "$PLAN_IMG" | wc -l | tr -d ' ')"
  ok "Update $name applied."
  echo "  Roll back:  sudo bash $0 --install-dir $INSTALL_DIR --rollback $name"
  echo "  Previous images are kept as <repository>:rollback-$RB_STAMP (remove them with 'docker image rm' when no longer needed)."
  cleanup_work; WORK=""
  return 0
}

for i in $CHOSEN; do process_bundle "$i"; done

step "Result"
( cd "$INSTALL_DIR" && METEOR_SETTINGS="$([ -f settings.json ] && cat settings.json || echo '{}')" $DC ps 2>/dev/null ) || true
echo
echo "================================================================"
echo " Update finished"
echo "================================================================"
echo " Install dir   : $INSTALL_DIR"
echo " History       : $HISTORY"
echo " Roll back     : sudo bash $0 --install-dir $INSTALL_DIR --rollback"
