#!/usr/bin/env bash
# SCLAB Studio Installation Script
# This script performs one-time configuration for secrets, domains, and license keys.
# 
# Files that will be modified:
# - Secrets: docker-compose.yml, common.env, settings.json, ai-service.env
# - Domain: common.env, nginx.conf, settings.json, mqtt-broker.env
# - License: settings.json
#
# Default placeholders that will be replaced:
#   - changeThisMongoPassword (MongoDB database password)
#   - changeThisRedisPassword (Redis cache password)
#   - changeThisQdrantApiKey (Qdrant vector database API key)
#   - openAiApiKeyHere (OpenAI API key - optional, leave empty for local models)
#   - yourdomain.com (Your domain name - optional, skip if using localhost)
#   - LICENSE CODE HERE (Your SCLAB license key - required)

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

# Check if installation has already been completed
if [[ -f "$INIT_FILE" ]]; then
  echo "[Info] Installation has already been completed (.init file exists)."
  echo "To reinstall with new settings, please delete the $INIT_FILE file and run this script again."
  exit 0
fi

# Generate a cryptographically secure 32-character alphanumeric password
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

# Prompt for password input (hidden for security). Press Enter to auto-generate a secure password.
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
    echo " → Using your custom password."
  else
    value="$(gen_secret)"
    echo " → Auto-generating secure password (32 random characters)."
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

echo "========================================"
echo "SCLAB STUDIO Installation"
echo "========================================"
echo ""
echo "This script will configure your SCLAB Studio installation."
echo "For security passwords, you can either:"
echo "  - Enter your own password, or"
echo "  - Press Enter to auto-generate a secure 32-character password"
echo

# License Key Configuration (REQUIRED)
echo ""
echo "License Key Configuration"
echo "------------------------"
echo "Please enter your SCLAB Studio license key."
echo "This is required to activate your installation."
read -r -s -p "License Key: " LICENSE_KEY || true
echo
if [[ ! "$LICENSE_KEY" =~ [^[:space:]] ]]; then
  echo "[Error] License key cannot be empty. Installation aborted."
  echo "Please obtain a valid license key and try again."
  exit 1
fi
echo " → License key accepted."

# Database and Service Passwords
echo ""
echo "Database and Service Configuration"
echo "----------------------------------"
echo "Configure passwords for the following services:"
echo ""
prompt_secret MONGO_PW   "MongoDB root password [Enter = auto-generate]: "
prompt_secret REDIS_PW   "Redis password [Enter = auto-generate]: "
prompt_secret QDRANT_KEY "Qdrant API key [Enter = auto-generate]: "

# AI Service Configuration
echo ""
echo "AI Service Configuration"
echo "------------------------"
echo "If you have an OpenAI API key, enter it to use GPT models."
echo "Leave empty to use local Ollama models instead."
read -r -s -p "OpenAI API Key [Enter = skip]: " OPENAI_KEY || true
echo
if [[ -n "${OPENAI_KEY:-}" ]]; then
  echo " → OpenAI API key configured. GPT models will be available."
else
  echo " → No OpenAI API key provided. Will use local Ollama models."
fi

# Editor Subdomain Configuration
echo ""
echo "Editor Subdomain Configuration"
echo "------------------------------"
echo "The mainPrefix allows you to host the editor interface on a separate subdomain."
echo "This is useful for separating the main site from the editor interface."
echo ""
echo "Examples:"
echo "  - If your domain is 'example.com' and mainPrefix is 'editor',"
echo "    the editor will be accessible at 'editor.example.com'"
echo "  - Leave empty to use the same domain for both site and editor"
echo ""
read -r -p "Editor subdomain prefix [Enter = none]: " MAIN_PREFIX || true
echo
if [[ -n "${MAIN_PREFIX:-}" ]]; then
  echo " → Editor will be accessible at: $MAIN_PREFIX.<your-domain>"
else
  echo " → Editor will use the same domain as the main site."
fi

# Domain Configuration
echo ""
echo "Domain Configuration"
echo "--------------------"
echo "Enter your domain name to configure SCLAB Studio for production use."
echo "This will update configuration files with your domain."
echo "Leave empty to keep the default 'yourdomain.com' placeholder."
echo ""
read -r -p "Your domain name [Enter = skip]: " DOMAIN_NEW || true
if [[ -n "${DOMAIN_NEW:-}" ]]; then
  echo " → Domain will be set to: $DOMAIN_NEW"
else
  echo " → Keeping default domain placeholder. Remember to update it later for production."
fi

# Administrator Account Configuration
echo ""
echo "Administrator Account Configuration"
echo "-----------------------------------"
echo "Configure the administrator account for SCLAB Studio."
echo ""
read -r -p "Admin email address [Enter = admin@sclab.io]: " ADMIN_EMAIL || true
if [[ -n "${ADMIN_EMAIL:-}" ]]; then
  echo " → Admin email set to: $ADMIN_EMAIL"
else
  ADMIN_EMAIL="admin@sclab.io"
  echo " → Using default admin email: $ADMIN_EMAIL"
fi

echo ""
echo "Admin password configuration:"
echo "You can either enter your own password or press Enter to auto-generate a secure one."
read -r -s -p "Admin password [Enter = auto-generate]: " ADMIN_PASSWORD || true
echo
if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
  echo " → Using your custom admin password."
else
  ADMIN_PASSWORD="$(gen_secret)"
  echo " → Auto-generated secure admin password."
fi

echo ""
echo "========================================"
echo "Applying Configuration"
echo "========================================"

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

# Update admin credentials in settings.json
if [[ -f "settings.json" ]]; then
  echo " - Updating administrator credentials in settings.json..."
  # Escape special characters in the replacement strings
  ADMIN_EMAIL_ESC="$(printf '%s' "${ADMIN_EMAIL}" | sed -e 's/[\\/&]/\\&/g')"
  ADMIN_PASSWORD_ESC="$(printf '%s' "${ADMIN_PASSWORD}" | sed -e 's/[\\/&]/\\&/g')"
  
  # Replace adminEmail value
  sed -i.bak -e 's/"adminEmail"[[:space:]]*:[[:space:]]*"[^"]*"/"adminEmail": "'"$ADMIN_EMAIL_ESC"'"/g' "settings.json"
  
  # Replace adminPassword value
  sed -i.bak -e 's/"adminPassword"[[:space:]]*:[[:space:]]*"[^"]*"/"adminPassword": "'"$ADMIN_PASSWORD_ESC"'"/g' "settings.json"
  
  rm -f "settings.json.bak"
  echo " - settings.json: updated admin credentials"
else
  echo " ! Warning: settings.json not found; could not update admin credentials."
fi

# Create .init (no secrets stored)
umask 077
{
  echo "initialized_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "files=${FILES[*]}"
  echo "domain_files=${DOMAIN_FILES[*]}"
  echo "license_file=$LICENSE_FILE"
} > "$INIT_FILE"

echo
echo "✅ Configuration completed successfully!"
echo ""
echo "Configuration has been saved. To reconfigure, delete the .init file and run this script again."

echo ""
echo "Generating security keys..."
echo "Creating JWT tokens and SSL certificates for secure communication..."
docker compose -f gen.yml run --rm key-generator

echo ""
echo "Installing AWS CLI..."
echo "AWS CLI is required for S3 storage functionality..."
if ! command -v aws >/dev/null 2>&1; then
  TMP="$(mktemp -d)"
  # Ensure cleanup on exit
  trap 'rm -rf "$TMP"' EXIT

  # Download to temp directory to avoid permission issues
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP/awscliv2.zip"

  # Install unzip if not available (Ubuntu/Debian)
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

echo ""
echo "Creating Docker network..."
echo "Setting up internal network for container communication..."
docker network create sclab-network || true

echo ""
echo "========================================"
echo "🎉 Installation Complete!"
echo "========================================"
echo ""
echo "SCLAB Studio has been successfully configured."
echo ""
echo "Next steps:"
echo "  1. Start SCLAB Studio:  sudo ./run.sh"
echo "  2. Stop SCLAB Studio:   sudo ./stop.sh"
echo "  3. View logs:           sudo ./logs.sh"
echo ""
echo "After starting, access SCLAB Studio at:"
if [[ -n "${DOMAIN_NEW:-}" ]]; then
  echo "  - Main site: https://$DOMAIN_NEW"
  if [[ -n "${MAIN_PREFIX:-}" ]]; then
    echo "  - Editor: https://$MAIN_PREFIX.$DOMAIN_NEW"
  fi
else
  echo "  - http://localhost (update domain for production use)"
fi
echo ""
echo "========================================"
echo "Administrator Login Credentials"
echo "========================================"
echo "Email:    $ADMIN_EMAIL"
echo "Password: $ADMIN_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Please change your password after first login!"
echo "   The password is stored in settings.json which could be exposed."
echo "   For security, update your password through the admin interface."
echo "========================================"
echo ""
