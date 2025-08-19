#!/usr/bin/env bash
# One-time secret & domain setup / replacement script
# Secrets in: docker-compose.yml, common.env, settings.json
# Domain only in: common.env, nginx.conf, settings.json, mqtt-broker.env
# License only in: settings.json
# Placeholders:
#   - changeThisMongoPassword
#   - changeThisRedisPassword
#   - changeThisQdrantApiKey
#   - openAiApiKeyHere (optional; Enter = empty)
#   - yourdomain.com  (optional; Enter = skip)
#   - LICENSE CODE HERE (required; abort if empty)

set -euo pipefail

# Check if running with sudo
if [[ $EUID -ne 0 ]]; then
   echo "[Error] This script must be run with sudo privileges."
   echo "Please run: sudo ./install.sh"
   exit 1
fi

INIT_FILE=".init"
FILES=("docker-compose.yml" "common.env" "settings.json" "ai-service.env")
DOMAIN_FILES=("common.env" "nginx.conf" "settings.json" "mqtt-broker.env")
LICENSE_FILE="settings.json"
LICENSE_PLACEHOLDER="LICENSE CODE HERE"

# Exit if already initialized
if [[ -f "$INIT_FILE" ]]; then
  echo "[Info] Already initialized (.init exists)."
  echo "To reset, delete $INIT_FILE and run this script again."
  exit 0
fi

# Generate a secure random 32-char alphanumeric secret
gen_secret() {
  # Temporarily disable pipefail to avoid SIGPIPE from 'head -c' killing the pipeline
  set +o pipefail
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
  fi
  set -o pipefail
}

# Prompt for a secret (silent). Enter = auto-generate a secure default.
prompt_secret() {
  local var_name="$1"
  local prompt_msg="$2"
  local typed=""
  local value=""

  # -s hides input; don't crash on Ctrl-D
  read -r -s -p "$prompt_msg" typed || true
  echo

  if [[ -n "$typed" ]]; then
    value="$typed"
    echo " → Using user-provided value."
  else
    value="$(gen_secret)"
    echo " → Enter pressed: applying secure auto-generated default."
  fi

  # Safe assignment (no eval)
  printf -v "$var_name" '%s' "$value"
}

# Replace placeholders across FILES
do_replace_all() {
  local placeholder="$1"
  local replacement="$2"
  local label="$3"
  local esc
  local found_any=0

  esc="$(printf '%s' "$replacement" | sed -e 's/[\\/&]/\\&/g')"

  for f in "${FILES[@]}"; do
    if [[ -f "$f" ]] && grep -qF "$placeholder" "$f"; then
      sed -i.bak -e "s@$placeholder@$esc@g" "$f"
      rm -f "${f}.bak"
      echo " - $f: replaced '$placeholder' with <$label>."
      found_any=1
    fi
  done

  if [[ "$found_any" -eq 0 ]]; then
    echo " ! Note: '$placeholder' not found in any of: ${FILES[*]}"
  fi
}

# Replace placeholders only in DOMAIN_FILES (with custom sed search)
do_replace_domain_only() {
  local placeholder="$1"   # grep needle (fixed string)
  local replacement="$2"
  local label="$3"
  local sed_search="$4"    # e.g., yourdomain\.com
  local esc
  local found_any=0

  esc="$(printf '%s' "$replacement" | sed -e 's/[\\/&]/\\&/g')"

  for f in "${DOMAIN_FILES[@]}"; do
    if [[ -f "$f" ]] && grep -qF "$placeholder" "$f"; then
      sed -i.bak -e "s@$sed_search@$esc@g" "$f"
      rm -f "${f}.bak"
      echo " - $f: replaced '$placeholder' with <$label>."
      found_any=1
    fi
  done

  if [[ "$found_any" -eq 0 ]]; then
    echo " ! Note: '$placeholder' not found in any of: ${DOMAIN_FILES[*]}"
  fi
}

# Replace placeholder only in LICENSE_FILE
do_replace_license_only() {
  local placeholder="$1"   # fixed string
  local replacement="$2"
  local label="$3"
  local esc
  local f="$LICENSE_FILE"

  if [[ ! -f "$f" ]]; then
    echo "[Error] '$f' not found; cannot write license key."
    exit 1
  fi
  if ! grep -qF "$placeholder" "$f"; then
    echo "[Error] '$placeholder' not found in '$f'; cannot write license key."
    exit 1
  fi

  esc="$(printf '%s' "$replacement" | sed -e 's/[\\/&]/\\&/g')"
  sed -i.bak -e "s@$placeholder@$esc@g" "$f"
  rm -f "${f}.bak"
  echo " - $f: replaced '$placeholder' with <$label>."
}

echo "SCLAB STUDIO Installation process start."
echo "Tip: For secrets, press Enter to auto-generate a secure 32-character default."
echo

# REQUIRED: License key (treat whitespace-only as empty)
read -r -s -p "Enter License Key for settings.json (REQUIRED): " LICENSE_KEY || true
echo
if [[ ! "$LICENSE_KEY" =~ [^[:space:]] ]]; then
  echo "[Error] License key is required. Aborting."
  exit 1
fi

# Ask for each secret (Enter = auto-generate)
prompt_secret MONGO_PW   "Enter MongoDB root password [Enter = auto-generate]: "
prompt_secret REDIS_PW   "Enter Redis password [Enter = auto-generate]: "
prompt_secret QDRANT_KEY "Enter Qdrant API key [Enter = auto-generate]: "

# Ask for OpenAI API key (Enter = empty)
read -r -s -p "Enter OpenAI API Key for common.env [Enter = empty]: " OPENAI_KEY || true
echo
if [[ -n "${OPENAI_KEY:-}" ]]; then
  echo " → Using provided OpenAI API key."
else
  echo " → No OpenAI API key provided, will use empty value."
fi

# Ask for mainPrefix (Enter = empty)
echo
echo "mainPrefix is used to set a different domain for the editor instead of using siteDomain."
echo "Example: If siteDomain is 'example.com' and mainPrefix is 'editor', editor will be at 'editor.example.com'"
read -r -p "Enter mainPrefix for settings.json [Enter = empty]: " MAIN_PREFIX || true
echo
if [[ -n "${MAIN_PREFIX:-}" ]]; then
  echo " → Using provided mainPrefix: $MAIN_PREFIX"
else
  echo " → No mainPrefix provided, will use empty value."
fi

# Optional domain replacement (visible input). Enter = skip
read -r -p "Enter domain to replace 'yourdomain.com' in {common.env, nginx.conf, settings.json, mqtt-broker.env} [Enter = skip]: " DOMAIN_NEW || true
if [[ -n "${DOMAIN_NEW:-}" ]]; then
  echo " → Will replace 'yourdomain.com' with the provided domain in the specified files."
else
  echo " → Skipping domain change."
fi

echo
echo "Replacing values..."

# Replace secrets across docker-compose.yml, common.env, settings.json
do_replace_all "changeThisMongoPassword"  "$MONGO_PW"   "MongoDB password"
do_replace_all "changeThisRedisPassword"  "$REDIS_PW"   "Redis password"
do_replace_all "changeThisQdrantApiKey"   "$QDRANT_KEY" "Qdrant API key"

# Replace OpenAI API key in common.env
OPENAI_REPLACEMENT="${OPENAI_KEY:-}"
do_replace_all "openAiApiKeyHere" "$OPENAI_REPLACEMENT" "OpenAI API key"

# If OpenAI API key is provided, update settings.json
if [[ -n "${OPENAI_KEY:-}" ]]; then
  echo " - Updating settings.json for OpenAI configuration..."
  
  # Update sqlModel to GPT5_MINI
  if [[ -f "settings.json" ]]; then
    # Replace sqlModel value
    sed -i.bak -e 's/"sqlModel"[[:space:]]*:[[:space:]]*"[^"]*"/"sqlModel": "GPT5_MINI"/g' "settings.json"
    
    # Replace hub.llmAPI value
    sed -i.bak -e 's/"llmAPI"[[:space:]]*:[[:space:]]*"[^"]*"/"llmAPI": "openai"/g' "settings.json"
    
    rm -f "settings.json.bak"
    echo " - settings.json: updated sqlModel to 'GPT5_MINI' and hub.llmAPI to 'openai'."
  else
    echo " ! Warning: settings.json not found; could not update AI configuration."
  fi
fi

# Replace domain only in specified files
if [[ -n "${DOMAIN_NEW:-}" ]]; then
  do_replace_domain_only "yourdomain.com" "$DOMAIN_NEW" "domain" "yourdomain\\.com"
fi

# Update mainPrefix in settings.json
if [[ -f "settings.json" ]]; then
  echo " - Updating mainPrefix in settings.json..."
  # Escape special characters in the replacement string
  MAIN_PREFIX_ESC="$(printf '%s' "${MAIN_PREFIX:-}" | sed -e 's/[\\/&]/\\&/g')"
  # Replace mainPrefix value
  sed -i.bak -e 's/"mainPrefix"[[:space:]]*:[[:space:]]*"[^"]*"/"mainPrefix": "'"$MAIN_PREFIX_ESC"'"/g' "settings.json"
  rm -f "settings.json.bak"
  echo " - settings.json: updated mainPrefix to '${MAIN_PREFIX:-}'"
else
  echo " ! Warning: settings.json not found; could not update mainPrefix."
fi

# Replace LICENSE CODE HERE only in settings.json (required)
do_replace_license_only "$LICENSE_PLACEHOLDER" "$LICENSE_KEY" "license key"

# Create .init (no secrets stored)
umask 077
{
  echo "initialized_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "files=${FILES[*]}"
  echo "domain_files=${DOMAIN_FILES[*]}"
  echo "license_file=$LICENSE_FILE"
} > "$INIT_FILE"

echo
echo "✅ Initialization complete! (.init created)"
echo "To re-run, delete .init and execute this script again."

echo "Make JWT and SSL key files"
docker compose -f gen.yml run --rm key-generator

echo "Install AWS CLI"
if ! command -v aws >/dev/null 2>&1; then
  TMP="$(mktemp -d)"
  # 삭제 보장
  trap 'rm -rf "$TMP"' EXIT

  # 다운로드(권한 문제 회피: /tmp 사용)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP/awscliv2.zip"

  # unzip 없으면 설치(우분투)
  if ! command -v unzip >/dev/null 2>&1; then
    echo "[Info] 'unzip' not found; installing..."
    apt-get update -y && apt-get install -y unzip
  fi

  unzip -q "$TMP/awscliv2.zip" -d "$TMP"
  "$TMP/aws/install" -i /usr/local/aws -b /usr/local/bin
  echo "[Info] AWS CLI installed: $(aws --version)"
else
  echo "[Info] AWS CLI already installed: $(aws --version)"
fi

echo "Create sclab-network"
docker network create sclab-network || true

echo "Installation complete."
echo "To start SCLAB : sudo ./run.sh"
echo "To stop SCLAB   : sudo ./stop.sh"
echo "Display logs    : sudo ./logs.sh"
