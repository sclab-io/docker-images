#!/usr/bin/env bash
# Turn optional SCLAB services on/off by adding/removing them in docker-compose.yml.
# Disabled services are not started, which saves CPU/memory. Works on any Linux with bash + awk.
#
#   ./service-manage.sh                      checkbox menu (arrows, Space, Enter, Esc/q)
#   ./service-manage.sh list                 show enabled/disabled state
#   ./service-manage.sh enable  <svc...>     add services to docker-compose.yml
#   ./service-manage.sh disable <svc...>     remove services from docker-compose.yml
#   ./service-manage.sh gmail                send mail through a Google account (sets MAIL_URL in common.env)
#
# The definition of each service is kept in optional-services/<name>.yml
# (tileserver: tileserver/docker-compose.tileserver.yml).
# After changing, apply with ./run.sh (it runs "docker compose up -d --remove-orphans",
# so containers of disabled services are removed).
#
# sclab-vision is a separate stack in ./vision (own docker-compose.yml and .env), so it is not
# edited in docker-compose.yml: enable runs vision/up.sh, disable runs vision/down.sh (data is kept).
# Install it first with: cd vision && ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE=docker-compose.yml
SNIPPET_DIR=optional-services
SERVICES="gis-process mqtt-client mqtt-broker kafka-client ai-service node-vm-service sclab-agent mail mongo redis qdrant tileserver sclab-vision"
VISION_DIR=vision
COMPOSE_CHANGED=0

describe() {
  case "$1" in
    gis-process)     echo "GIS data processing" ;;
    mqtt-client)     echo "MQTT client (subscribes to external brokers)" ;;
    mqtt-broker)     echo "Built-in MQTT broker (ports 8883, 8888)" ;;
    kafka-client)    echo "Kafka client" ;;
    ai-service)      echo "AI service (LLM / vector search)" ;;
    node-vm-service) echo "Node.js sandbox for scripts" ;;
    sclab-agent)     echo "DB agent (connects to external databases)" ;;
    mail)            echo "SMTP relay for outgoing mail (MAIL_URL=smtp://mail:25)" ;;
    mongo)           echo "MongoDB (bundled; disable when using an external MongoDB)" ;;
    redis)           echo "Redis (bundled; disable when using an external Redis)" ;;
    qdrant)          echo "Qdrant vector DB (needed by ai-service and sclab-vision)" ;;
    tileserver)      echo "Map tile server (tileserver + tileserver-edge, ~95 GB image)" ;;
    sclab-vision)    echo "SCLAB Vision stack (vision-aio, vision-console; ./vision)" ;;
  esac
}

# Compose services that make up one entry (tileserver is two services).
members() {
  case "$1" in
    tileserver) echo "tileserver tileserver-edge" ;;
    *)          echo "$1" ;;
  esac
}

snippet_path() {
  case "$1" in
    tileserver) echo "tileserver/docker-compose.tileserver.yml" ;;
    *)          echo "$SNIPPET_DIR/$1.yml" ;;
  esac
}

is_stack() {
  [ "$1" = "sclab-vision" ]
}

is_known() {
  local s
  for s in $SERVICES; do [ "$s" = "$1" ] && return 0; done
  return 1
}

is_enabled() {
  if is_stack "$1"; then
    command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'vision-aio'
    return
  fi
  grep -qE "^  $(members "$1" | cut -d' ' -f1):[[:space:]]*$" "$COMPOSE"
}

# Replace $COMPOSE with the contents of file $1 (keeps the original file's mode/owner).
replace_compose() {
  cat "$1" > "$COMPOSE"
  rm -f "$1"
}

# Drop depends_on entries that point to services which are not defined (and empty depends_on keys),
# otherwise "docker compose" refuses to start.
prune_depends_on() {
  local tmp
  tmp=$(mktemp "${COMPOSE}.XXXXXX")
  awk '
    NR == FNR {
      if ($0 ~ /^  [A-Za-z0-9_-]+:[ \t]*$/) { n = $0; sub(/^  /, "", n); sub(/:.*/, "", n); defined[n] = 1 }
      next
    }
    function flush(   i) {
      if (cnt > 0) { print hdr; for (i = 1; i <= cnt; i++) print keep[i] }
      in_dep = 0; cnt = 0
    }
    in_dep {
      if ($0 ~ /^      - /) {
        n = $0; sub(/^      - /, "", n); gsub(/["\047 \t]/, "", n)
        if (n in defined) keep[++cnt] = $0
        next
      }
      flush()
    }
    /^    depends_on:[ \t]*$/ { in_dep = 1; hdr = $0; cnt = 0; next }
    { print }
    END { if (in_dep) flush() }
  ' "$COMPOSE" "$COMPOSE" > "$tmp"
  replace_compose "$tmp"
}

# Replace every occurrence of a literal placeholder in docker-compose.yml.
replace_placeholder() {
  local tmp
  tmp=$(mktemp "${COMPOSE}.XXXXXX")
  FROM="$1" TO="$2" awk '
    BEGIN { f = ENVIRON["FROM"]; t = ENVIRON["TO"]; n = length(f) }
    { out = ""; rest = $0
      while ((i = index(rest, f)) > 0) { out = out substr(rest, 1, i - 1) t; rest = substr(rest, i + n) }
      print out rest }
  ' "$COMPOSE" > "$tmp"
  replace_compose "$tmp"
}

# Value of KEY in an env file, without surrounding quotes.
env_value() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1 | tr -d "\"'" || true
}

# The snippets carry install-time placeholders; put back the real secrets that install.sh stored in the env files.
restore_secret() {
  local value=""
  case "$1" in
    mongo)
      # MONGO_URL=mongodb://root:<password>@mongo:27017/...  (only when it points to the bundled container)
      value=$(env_value common.env MONGO_URL | sed -n 's#^mongodb://root:\(.*\)@mongo:27017.*#\1#p')
      [ -n "$value" ] || echo "   Note: MONGO_URL in common.env does not point to the bundled mongo; update it (or the password in $COMPOSE)."
      [ -z "$value" ] || [ "$value" = "changeThisMongoPassword" ] || replace_placeholder changeThisMongoPassword "$value"
      ;;
    redis)
      value=$(env_value ai-service.env REDIS_PASSWORD)
      if env_value ai-service.env REDIS_URL | grep -q '^redis://redis:'; then
        [ -z "$value" ] || [ "$value" = "changeThisRedisPassword" ] || replace_placeholder changeThisRedisPassword "$value"
      else
        echo "   Note: REDIS_URL in ai-service.env and redisOplog in settings.json do not point to the bundled redis; update them."
      fi
      ;;
    qdrant)
      value=$(env_value common.env QDRANT_API_KEY)
      [ -z "$value" ] || [ "$value" = "changeThisQdrantApiKey" ] || replace_placeholder changeThisQdrantApiKey "$value"
      if ! env_value common.env QDRANT_CLUSTER_URL | grep -q '^http://qdrant:'; then
        echo "   Note: QDRANT_CLUSTER_URL in common.env does not point to the bundled qdrant; update it."
      fi
      ;;
  esac
}

enable_service() {
  local name="$1" snippet tmp
  snippet=$(snippet_path "$name")
  if is_enabled "$name"; then
    echo " - $name: already enabled."
    return 0
  fi
  if is_stack "$name"; then
    enable_stack
    return
  fi
  if [ ! -f "$snippet" ]; then
    echo "[Error] $snippet not found." >&2
    return 1
  fi
  grep -qE '^networks:' "$COMPOSE" || { echo "[Error] 'networks:' section not found in $COMPOSE" >&2; return 1; }

  # Insert the snippet (without its # comment lines) right before the top-level networks: block.
  tmp=$(mktemp "${COMPOSE}.XXXXXX")
  awk -v snippet="$snippet" '
    /^networks:/ && !done {
      while ((getline line < snippet) > 0) { if (line !~ /^#/) print line }
      close(snippet)
      print ""
      done = 1
    }
    { print }
  ' "$COMPOSE" > "$tmp"
  replace_compose "$tmp"
  prune_depends_on
  restore_secret "$name"
  COMPOSE_CHANGED=1
  echo " - $name: enabled (added to $COMPOSE)."
  if [ "$name" = "qdrant" ]; then
    echo "   Note: webapp / ai-service no longer list qdrant in depends_on; they reconnect on their own (restart: always)."
  fi
  if [ "$name" = "tileserver" ]; then
    echo "   Also set public.tileServerURL in settings.json and TILESERVER_ALLOWED_REFERERS in tileserver.env."
  fi
}

disable_service() {
  local name="$1" tmp member
  if ! is_enabled "$name"; then
    echo " - $name: already disabled."
    return 0
  fi
  if is_stack "$name"; then
    disable_stack
    return
  fi
  for member in $(members "$name"); do
    tmp=$(mktemp "${COMPOSE}.XXXXXX")
    awk -v n="$member" '
      skip && !($0 ~ /^  [A-Za-z0-9_-]+:[ \t]*$/ || $0 ~ /^[^ \t]/) { next }
      skip { skip = 0; if (last != "") print "" }
      $0 ~ "^  " n ":[ \t]*$" { skip = 1; next }
      { print; last = $0 }
    ' "$COMPOSE" > "$tmp"
    replace_compose "$tmp"
  done
  prune_depends_on
  COMPOSE_CHANGED=1
  echo " - $name: disabled (removed from $COMPOSE)."
  if [ "$name" = "mail" ] && [ -z "${SERVICE_MANAGE_QUIET:-}" ] && [ -t 0 ] && [ -t 1 ]; then
    echo "   MAIL_URL still points to the removed 'mail' service."
    local answer=""
    read -r -p "   Send mail through Gmail instead? [y/N]: " answer || answer=""
    case "$answer" in [Yy]*) configure_gmail ;; esac
  fi
}

# Percent-encode a string for use inside a URL (userinfo part).
url_encode() {
  local str="$1" out="" c i
  local LC_ALL=C
  for ((i = 0; i < ${#str}; i++)); do
    c="${str:i:1}"
    case "$c" in
      [A-Za-z0-9._~-]) out+="$c" ;;
      *) out+=$(printf '%%%02X' $(( $(printf '%d' "'$c") & 255 ))) ;;
    esac
  done
  printf '%s' "$out"
}

# Set KEY=value in an env file, keeping the double quotes if the existing line used them.
set_env_value() {
  local file="$1" key="$2" value="$3" tmp
  tmp=$(mktemp "${file}.XXXXXX")
  KEY="$key" VALUE="$value" awk '
    BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"] }
    index($0, k "=") == 1 {
      if (substr($0, length(k) + 2, 1) == "\"") print k "=\"" v "\""
      else print k "=" v
      next
    }
    { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# Send mail through a Google account: MAIL_URL=smtps://<user>:<app password>@smtp.gmail.com:465 in common.env.
configure_gmail() {
  local user="" pass=""
  if [ ! -f common.env ]; then
    echo "[Error] common.env not found." >&2
    return 1
  fi
  echo ""
  echo "Gmail SMTP (smtp.gmail.com). This needs an App Password:"
  echo "Google Account > Security > 2-Step Verification > App passwords (a normal password does not work)."
  read -r -p "Gmail address (Enter = cancel): " user || user=""
  if [ -z "$user" ]; then
    echo " - Gmail: cancelled, MAIL_URL unchanged."
    return 0
  fi
  while [ -z "$pass" ]; do
    read -r -s -p "Gmail App Password (16 characters): " pass || pass=""
    echo
    pass="${pass//[[:space:]]/}"
  done
  set_env_value common.env MAIL_URL "smtps://$(url_encode "$user"):$(url_encode "$pass")@smtp.gmail.com:465"
  COMPOSE_CHANGED=1
  echo " - common.env: MAIL_URL set to Gmail SMTP as $user."
}

# sclab-vision: separate compose project in ./vision; act on it right away.
enable_stack() {
  if [ ! -f "$VISION_DIR/.env" ]; then
    echo "[Error] sclab-vision is not installed ($VISION_DIR/.env not found). Run: cd $VISION_DIR && ./install.sh" >&2
    return 1
  fi
  (cd "$VISION_DIR" && ./up.sh)
  echo " - sclab-vision: enabled (started)."
}

disable_stack() {
  (cd "$VISION_DIR" && ./down.sh)
  echo " - sclab-vision: disabled (containers removed, data in $VISION_DIR/data is kept)."
}

list_services() {
  local s i=0 state
  for s in $SERVICES; do
    i=$((i + 1))
    if is_enabled "$s"; then state="ON "; else state="off"; fi
    printf '  %d) [%s] %-16s %s\n' "$i" "$state" "$s" "$(describe "$s")"
  done
}

# Map a name or list number to a service name.
resolve() {
  local arg="$1" i=0 s
  if is_known "$arg"; then echo "$arg"; return 0; fi
  case "$arg" in
    ''|*[!0-9]*) return 1 ;;
  esac
  for s in $SERVICES; do
    i=$((i + 1))
    [ "$i" -eq "$arg" ] && { echo "$s"; return 0; }
  done
  return 1
}

apply_hint() {
  [ "$COMPOSE_CHANGED" -eq 1 ] || return 0
  echo ""
  echo "Apply the change with: sudo ./run.sh   (containers of disabled services are removed)"
}

# Fallback menu for when stdin/stdout is not a terminal.
interactive_basic() {
  local input arg name changed
  while true; do
    echo ""
    echo "Optional services (ON = in $COMPOSE / running):"
    list_services
    echo ""
    read -r -p "Numbers or names to toggle (space separated, Enter = quit): " input || input=""
    [ -z "$input" ] && break
    changed=0
    for arg in $input; do
      if ! name=$(resolve "$arg"); then
        echo " ! Unknown service: $arg"
        continue
      fi
      if is_enabled "$name"; then disable_service "$name"; else enable_service "$name"; fi
      changed=1
    done
    [ "$changed" -eq 1 ] && apply_hint
  done
}

# Seconds to wait for the rest of an escape sequence (a lone Esc key). bash 3.2 (macOS) has no fractional timeouts.
esc_timeout() {
  if [ -z "$( { read -r -t 0.05 _unused </dev/null; } 2>&1 )" ]; then echo 0.05; else echo 1; fi
}

# Read one key into KEY: up, down, space, enter, quit, other.
read_key() {
  local k rest=""
  KEY=other
  IFS= read -rsn1 k || { KEY=quit; return 0; }
  case "$k" in
    $'\033')
      IFS= read -rsn2 -t "$ESC_TIMEOUT" rest || true
      case "$rest" in
        '')          KEY=quit ;;
        '[A'|'OA')   KEY=up ;;
        '[B'|'OB')   KEY=down ;;
        *)           KEY=other ;;
      esac
      ;;
    '')    KEY=enter ;;
    ' ')   KEY=space ;;
    q|Q)   KEY=quit ;;
    k)     KEY=up ;;
    j)     KEY=down ;;
  esac
  return 0
}

# Checkbox menu: arrows move, space toggles, Enter applies, Esc/q quits without changes.
interactive_tui() {
  local -a items=($SERVICES) cur=() sel=()
  local n=${#items[@]} i pos=0 first=1 lines mark line action
  ESC_TIMEOUT=$(esc_timeout)

  for ((i = 0; i < n; i++)); do
    if is_enabled "${items[$i]}"; then cur[$i]=1; else cur[$i]=0; fi
    sel[$i]=${cur[$i]}
  done
  lines=$((n + 4))

  printf '\033[?25l'
  trap 'printf "\033[?25h"' EXIT
  trap 'printf "\033[?25h\n"; exit 130' INT TERM

  while true; do
    [ "$first" -eq 1 ] || printf '\033[%dA' "$lines"
    first=0
    printf '\033[K\n'
    printf '\033[K  \033[1mOptional services\033[0m\n'
    printf '\033[K  \033[2m↑/↓ move   Space check/uncheck   Enter apply   Esc/q quit\033[0m\n'
    for ((i = 0; i < n; i++)); do
      if [ "${sel[$i]}" -eq 1 ]; then mark="[x]"; else mark="[ ]"; fi
      action=""
      if [ "${sel[$i]}" -ne "${cur[$i]}" ]; then
        if [ "${sel[$i]}" -eq 1 ]; then action=" → will enable"; else action=" → will disable"; fi
      fi
      line=$(printf '%s %-16s %s%s' "$mark" "${items[$i]}" "$(describe "${items[$i]}")" "$action")
      if [ "$i" -eq "$pos" ]; then
        printf '\033[K \033[36m>\033[0m \033[7m%s\033[0m\n' "$line"
      else
        printf '\033[K   %s\n' "$line"
      fi
    done
    printf '\033[K\n'

    read_key
    case "$KEY" in
      up)    pos=$(( (pos + n - 1) % n )) ;;
      down)  pos=$(( (pos + 1) % n )) ;;
      space) sel[$pos]=$(( 1 - sel[$pos] )) ;;
      quit)
        printf '\033[?25h'
        trap - EXIT INT TERM
        echo "Quit without changes."
        return 0
        ;;
      enter) break ;;
    esac
  done

  printf '\033[?25h'
  trap - EXIT INT TERM

  local changed=0
  for ((i = 0; i < n; i++)); do
    [ "${sel[$i]}" -ne "${cur[$i]}" ] || continue
    changed=1
    if [ "${sel[$i]}" -eq 1 ]; then
      enable_service "${items[$i]}" || echo " ! ${items[$i]}: failed to enable."
    else
      disable_service "${items[$i]}" || echo " ! ${items[$i]}: failed to disable."
    fi
  done
  if [ "$changed" -eq 0 ]; then echo "No changes."; else apply_hint; fi
}

interactive() {
  if [ -t 0 ] && [ -t 1 ]; then interactive_tui; else interactive_basic; fi
}

usage() {
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Services: $SERVICES"
}

main() {
  [ -f "$COMPOSE" ] || { echo "[Error] $COMPOSE not found." >&2; exit 1; }

  local cmd="${1:-}"
  case "$cmd" in
    "")
      interactive
      ;;
    list|status)
      list_services
      ;;
    enable|disable|on|off)
      shift
      [ "$#" -gt 0 ] || { echo "[Error] Specify at least one service (or 'all')." >&2; usage >&2; exit 1; }
      local targets="" arg name rc=0
      for arg in "$@"; do
        if [ "$arg" = "all" ]; then targets="$targets $SERVICES"; continue; fi
        if ! name=$(resolve "$arg"); then
          echo "[Error] Unknown service: $arg" >&2
          rc=1
          continue
        fi
        targets="$targets $name"
      done
      [ "$rc" -eq 0 ] || exit 1
      for name in $targets; do
        case "$cmd" in
          enable|on) enable_service "$name" ;;
          *)         disable_service "$name" ;;
        esac
      done
      # install.sh calls this with SERVICE_MANAGE_QUIET=1 and prints its own guidance.
      [ -n "${SERVICE_MANAGE_QUIET:-}" ] || apply_hint
      ;;
    gmail)
      configure_gmail
      apply_hint
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "[Error] Unknown command: $cmd" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
