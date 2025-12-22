#!/usr/bin/env bash
# SCLAB Studio Installation Script
# Compatible with all major Linux distributions

set -euo pipefail

# Distribution detection
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
  elif [ -f /etc/redhat-release ]; then
    DISTRO_ID="rhel"
    DISTRO_ID_LIKE="rhel"
  elif [ -f /etc/debian_version ]; then
    DISTRO_ID="debian"
    DISTRO_ID_LIKE="debian"
  else
    DISTRO_ID="unknown"
    DISTRO_ID_LIKE=""
  fi
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Install package based on distribution
install_package() {
  local package="$1"
  echo "[Info] Installing $package..."
  
  if command_exists apt-get; then
    apt-get update -y && apt-get install -y "$package"
  elif command_exists yum; then
    yum install -y "$package"
  elif command_exists dnf; then
    dnf install -y "$package"
  elif command_exists zypper; then
    zypper install -y "$package"
  elif command_exists pacman; then
    pacman -Sy --noconfirm "$package"
  elif command_exists apk; then
    apk add --no-cache "$package"
  else
    echo "[Error] Unable to install $package. No supported package manager found."
    echo "Please install $package manually and run this script again."
    exit 1
  fi
}

# Install Docker if not present
install_docker() {
  echo "Installing Docker..."
  
  # Detect distribution for Docker installation
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu|debian)
        # Install prerequisites
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        curl -fsSL "https://download.docker.com/linux/$ID/gpg" | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Set up the stable repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        ;;
        
      fedora)
        # Install prerequisites
        dnf -y install dnf-plugins-core
        
        # Set up the repository
        dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        
        # Install Docker Engine
        dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Start Docker
        systemctl start docker
        systemctl enable docker
        ;;
        
      centos|rhel|rocky|almalinux)
        # Install prerequisites
        yum install -y yum-utils
        
        # Set up the repository
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        
        # Install Docker Engine
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Start Docker
        systemctl start docker
        systemctl enable docker
        ;;
        
      suse|opensuse*)
        # Install Docker using zypper
        zypper install -y docker docker-compose
        
        # Start Docker
        systemctl start docker
        systemctl enable docker
        ;;
        
      arch|manjaro)
        # Install Docker using pacman
        pacman -Sy --noconfirm docker docker-compose
        
        # Start Docker
        systemctl start docker
        systemctl enable docker
        ;;
        
      alpine)
        # Install Docker using apk
        apk add --no-cache docker docker-compose
        
        # Start Docker
        rc-update add docker boot
        service docker start
        ;;
        
      *)
        echo "[Error] Automatic Docker installation not supported for distribution: $ID"
        echo "Please install Docker manually: https://docs.docker.com/engine/install/"
        echo ""
        echo "Detected distribution: $ID"
        echo "You can find installation instructions at:"
        echo "https://docs.docker.com/engine/install/#server"
        exit 1
        ;;
    esac
    
    # Add current user to docker group (if not root)
    if [ -n "${SUDO_USER:-}" ]; then
      usermod -aG docker "$SUDO_USER"
      echo "[Info] Added user $SUDO_USER to docker group. You may need to log out and back in."
    fi
    
    # Start Docker service
    if command_exists systemctl; then
      systemctl start docker
      systemctl enable docker
    elif command_exists service; then
      service docker start
    fi
    
    echo "✓ Docker installed successfully"
  else
    echo "[Error] Cannot determine distribution. Please install Docker manually."
    echo "Visit: https://docs.docker.com/engine/install/"
    exit 1
  fi
}

# Check for required commands
check_requirements() {
  echo "Checking system requirements..."
  
  # Check if running as root
  if [ "$(id -u)" -ne 0 ]; then
    echo "[Error] This script must be run with sudo privileges."
    echo "Please run: sudo ./install.sh"
    exit 1
  fi
  
  # Check for Docker
  if ! command_exists docker; then
    echo "[Warning] Docker is not installed."
    echo ""
    read -r -p "Would you like to install Docker now? [Y/n]: " INSTALL_DOCKER
    case "${INSTALL_DOCKER:-Y}" in
      [Yy]* )
        install_docker
        ;;
      * )
        echo "[Error] Docker is required. Please install it manually."
        echo "Visit: https://docs.docker.com/engine/install/"
        exit 1
        ;;
    esac
  fi
  
  # Check for docker compose
  if command_exists docker; then
    if docker compose version >/dev/null 2>&1; then
      DOCKER_COMPOSE="docker compose"
    elif command_exists docker-compose; then
      DOCKER_COMPOSE="docker-compose"
    else
      echo "[Warning] Docker Compose not found."
      # Try to install docker-compose-plugin
      case "$DISTRO_ID" in
        ubuntu|debian)
          apt-get update && apt-get install -y docker-compose-plugin
          ;;
        fedora)
          dnf install -y docker-compose-plugin
          ;;
        centos|rhel|rocky|almalinux)
          yum install -y docker-compose-plugin
          ;;
        suse|opensuse*)
          zypper install -y docker-compose
          ;;
        arch|manjaro)
          pacman -Sy --noconfirm docker-compose
          ;;
        alpine)
          apk add --no-cache docker-compose
          ;;
        *)
          echo "[Error] Please install Docker Compose plugin manually."
          echo "Visit: https://docs.docker.com/compose/install/"
          exit 1
          ;;
      esac
      
      if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
      else
        echo "[Error] Failed to install Docker Compose."
        exit 1
      fi
    fi
  fi
  
  # Check for other required commands
  local required_commands="curl sed grep"
  for cmd in $required_commands; do
    if ! command_exists "$cmd"; then
      echo "[Warning] Required command not found: $cmd"
      case "$cmd" in
        curl)
          if command_exists wget; then
            echo "[Info] wget is available as an alternative to curl"
          else
            # Try to install curl
            install_package curl
          fi
          ;;
        *)
          install_package "$cmd"
          ;;
      esac
    fi
  done
  
  echo "✓ All requirements satisfied"
}

# Detect system architecture
detect_architecture() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64)
      ARCH_NORMALIZED="x86_64"
      ;;
    aarch64|arm64)
      ARCH_NORMALIZED="aarch64"
      ;;
    *)
      echo "[Warning] Unsupported architecture: $ARCH"
      echo "AWS CLI installation might fail."
      ARCH_NORMALIZED="$ARCH"
      ;;
  esac
}

# Download file with curl or wget
download_file() {
  local url="$1"
  local output="$2"
  
  if command_exists curl; then
    curl -fsSL "$url" -o "$output"
  elif command_exists wget; then
    wget -q "$url" -O "$output"
  else
    echo "[Error] Neither curl nor wget found. Cannot download files."
    exit 1
  fi
}

# Safe sed in-place replacement
safe_sed_inplace() {
  local file="$1"
  local search="$2"
  local replace="$3"
  local escaped_replace
  
  # Escape replacement for sed (@ delimiter, and & backrefs)
  escaped_replace=$(printf '%s' "$replace" | sed -e 's/[\\&@]/\\&/g')
  
  # Create backup
  cp "$file" "${file}.bak"
  
  # Use sed with proper escaping
  if sed --version 2>&1 | grep -q "GNU sed"; then
    # GNU sed
    sed -i "s@${search}@${escaped_replace}@g" "$file"
  else
    # BSD/other sed - try different approaches
    if sed -i'' "s@${search}@${escaped_replace}@g" "$file" 2>/dev/null; then
      :
    elif sed -i '' "s@${search}@${escaped_replace}@g" "$file" 2>/dev/null; then
      :
    else
      # Fallback: use temp file
      sed "s@${search}@${escaped_replace}@g" "${file}.bak" > "$file"
    fi
  fi
  
  # Remove backup
  rm -f "${file}.bak"
}

# Safe password input
read_password() {
  local prompt="$1"
  local var_name="$2"
  local password
  
  # Try to use read -s if available
  if echo | read -r -s 2>/dev/null; then
    read -r -s -p "$prompt" password || password=""
    echo
  else
    # Fallback: disable echo manually
    if command_exists stty; then
      printf "%s" "$prompt"
      stty -echo 2>/dev/null || true
      IFS= read -r password || password=""
      stty echo 2>/dev/null || true
      echo
    else
      # Last resort: visible password
      echo "[Warning] Password will be visible while typing!"
      IFS= read -r -p "$prompt" password || password=""
    fi
  fi
  
  # Use printf to safely assign the value
  printf -v "$var_name" '%s' "${password}"
}

INIT_FILE=".init"
FILES=("docker-compose.yml" "common.env" "settings.json" "ai-service.env" "redis.conf")
DOMAIN_FILES=("common.env" "nginx.conf" "settings.json" "mqtt-broker.env")
LICENSE_FILE="settings.json"
LICENSE_PLACEHOLDER="LICENSE CODE HERE"

# Main installation starts here
main() {
  detect_distro
  echo "Detected distribution: $DISTRO_ID (like: $DISTRO_ID_LIKE)"
  
  check_requirements
  detect_architecture
  echo "Detected architecture: $ARCH_NORMALIZED"
  
  # Check if already initialized
  if [ -f "$INIT_FILE" ]; then
    echo "[Info] Installation has already been completed (.init file exists)."
    echo "To reinstall with new settings, please delete the $INIT_FILE file and run this script again."
    exit 0
  fi
  
  # Generate a cryptographically secure 32-character alphanumeric password
  gen_secret() {
    if command_exists openssl; then
      openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
    elif [ -f /dev/urandom ]; then
      LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
    else
      # Fallback: use date and process ID (less secure)
      echo "[Warning] Using less secure password generation method"
      date +%s%N | sha256sum | base64 | head -c 32
    fi
  }
  
  # Prompt for password input (hidden for security)
  prompt_secret() {
    local var_name="$1"
    local prompt_msg="$2"
    local typed=""
    
    read_password "$prompt_msg" typed
    
    if [ -n "$typed" ]; then
      eval "$var_name=\"\$typed\""
      echo " → Using your custom password."
    else
      eval "$var_name=\"\$(gen_secret)\""
      echo " → Auto-generating secure password (32 random characters)."
    fi
  }
  
  # Replace placeholders across FILES
  do_replace_all() {
    local placeholder="$1"
    local replacement="$2"
    local label="$3"
    local found_any=0
    
    for f in "${FILES[@]}"; do
      if [ -f "$f" ] && grep -qF "$placeholder" "$f"; then
        safe_sed_inplace "$f" "$placeholder" "$replacement"
        echo " - $f: replaced '$placeholder' with <$label>."
        found_any=1
      fi
    done
    
    if [ "$found_any" -eq 0 ]; then
      echo " ! Note: '$placeholder' not found in any of: ${FILES[*]}"
    fi
  }
  
  # Replace placeholders only in DOMAIN_FILES
  do_replace_domain_only() {
    local placeholder="$1"
    local replacement="$2"
    local label="$3"
    local sed_search="$4"
    local found_any=0
    
    for f in "${DOMAIN_FILES[@]}"; do
      if [ -f "$f" ] && grep -qF "$placeholder" "$f"; then
        safe_sed_inplace "$f" "$sed_search" "$replacement"
        echo " - $f: replaced '$placeholder' with <$label>."
        found_any=1
      fi
    done
    
    if [ "$found_any" -eq 0 ]; then
      echo " ! Note: '$placeholder' not found in any of: ${DOMAIN_FILES[*]}"
    fi
  }
  
  # Replace placeholder only in LICENSE_FILE
  do_replace_license_only() {
    local placeholder="$1"
    local replacement="$2"
    local label="$3"
    local f="$LICENSE_FILE"
    
    if [ ! -f "$f" ]; then
      echo "[Error] '$f' not found; cannot write license key."
      exit 1
    fi
    if ! grep -qF "$placeholder" "$f"; then
      echo "[Error] '$placeholder' not found in '$f'; cannot write license key."
      exit 1
    fi
    
    safe_sed_inplace "$f" "$placeholder" "$replacement"
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
  
  # License Key Configuration (REQUIRED)
  echo ""
  echo "License Key Configuration"
  echo "------------------------"
  echo "Please enter your SCLAB Studio license key."
  echo "This is required to activate your installation."
  read_password "License Key: " LICENSE_KEY
  
  # Check if license key is empty (only whitespace)
  case "$LICENSE_KEY" in
    *[!\ \	]*) 
      echo " → License key accepted."
      ;;
    *)
      echo "[Error] License key cannot be empty. Installation aborted."
      echo "Please obtain a valid license key and try again."
      exit 1
      ;;
  esac

  # Install AWS CLI
  echo ""
  echo "Installing AWS CLI..."
  echo "AWS CLI is required for S3 storage functionality..."
  AWS_CMD="aws"
  if ! command_exists aws; then
    # Create temp directory
    TMP=$(mktemp -d 2>/dev/null || mktemp -d -t sclab.XXXXXX || echo "/tmp/sclab-$$")
    mkdir -p "$TMP"

    # Ensure cleanup on exit
    cleanup() {
      [ -d "$TMP" ] && rm -rf "$TMP"
    }
    trap cleanup EXIT INT TERM

    # Download AWS CLI
    case "$ARCH_NORMALIZED" in
      x86_64)
        AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
        ;;
      aarch64)
        AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
        ;;
      *)
        echo "[Warning] AWS CLI might not be available for architecture: $ARCH_NORMALIZED"
        AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
        ;;
    esac

    download_file "$AWS_URL" "$TMP/awscliv2.zip"

    # Install unzip if needed
    if ! command_exists unzip; then
      install_package unzip
    fi

    unzip -q "$TMP/awscliv2.zip" -d "$TMP"
    "$TMP/aws/install" -i /usr/local/aws -b /usr/local/bin

    # Fix permissions for AWS CLI - ensure all files are accessible
    chmod -R 755 /usr/local/aws
    chmod +x /usr/local/bin/aws

    # Find and fix the actual aws binary
    if [ -L /usr/local/aws/v2/current/bin/aws ]; then
      # Follow symlinks to find the actual binary
      AWS_ACTUAL=$(readlink -f /usr/local/aws/v2/current/bin/aws)
      if [ -f "$AWS_ACTUAL" ]; then
        chmod +x "$AWS_ACTUAL"
      fi
    fi

    AWS_CMD="$(command -v aws 2>/dev/null || echo /usr/local/bin/aws)"
    echo "[Info] AWS CLI installed: $("$AWS_CMD" --version)"
  else
    AWS_CMD="$(command -v aws)"
    echo "[Info] AWS CLI already installed: $("$AWS_CMD" --version)"
  fi

  # Check AWS credentials
  echo ""
  echo "Checking AWS credentials..."

  # Check if credentials file exists and has content
  AWS_CREDS_FILE="${HOME}/.aws/credentials"

  if [ -f "$AWS_CREDS_FILE" ] && grep -q "aws_access_key_id" "$AWS_CREDS_FILE" 2>/dev/null; then
    echo "✓ AWS credentials found"
  else
    echo "AWS credentials not found."
    echo "AWS credentials are required to download SCLAB docker images."
    echo ""
    read -r -p "Would you like to configure AWS credentials now? [Y/n]: " CONFIGURE_AWS
    case "${CONFIGURE_AWS:-Y}" in
      [Yy]* )
        echo ""
        echo "Please enter your AWS credentials:"
        echo "(These will be provided by SCLAB support)"

        "$AWS_CMD" configure

        # Verify credentials were configured
        if [ -f "$AWS_CREDS_FILE" ] && grep -q "aws_access_key_id" "$AWS_CREDS_FILE" 2>/dev/null; then
          echo "✓ AWS credentials configured successfully"
        else
          echo "[Warning] AWS credentials were not configured properly."
          echo "You may need to configure them manually later using: aws configure"
        fi
        ;;
      * )
        echo "[Warning] Skipping AWS configuration."
        echo "You will need to configure AWS credentials manually later using: aws configure"
        echo "Without AWS credentials, you won't be able to download SCLAB docker images."
        ;;
    esac
  fi
  
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
  echo "Leave empty to skip OpenAI."
  read_password "OpenAI API Key [Enter = skip]: " OPENAI_KEY
  if [ -n "${OPENAI_KEY:-}" ]; then
    echo " → OpenAI API key configured. GPT models will be available."
  else
    echo " → No OpenAI API key provided."
  fi
  echo ""
  echo "If you have a Gemini API key, enter it to use Gemini models."
  read_password "Gemini API Key [Enter = skip]: " GEMINI_API_KEY
  if [ -n "${GEMINI_API_KEY:-}" ]; then
    echo " → Gemini API key configured. Gemini models will be available."
  else
    echo " → No Gemini API key provided."
  fi
  if [ -z "${OPENAI_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
    echo " → No OpenAI/Gemini API key provided. Will use local Ollama models."
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
  if [ -n "${DOMAIN_NEW:-}" ]; then
    echo " → Domain will be set to: $DOMAIN_NEW"
  else
    echo " → Keeping default domain placeholder. Remember to update it later for production."
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
  if [ -n "${MAIN_PREFIX:-}" ]; then
    echo " → Editor will be accessible at: $MAIN_PREFIX.<your-domain>"
  else
    echo " → Editor will use the same domain as the main site."
  fi
  
  # Administrator Account Configuration
  echo ""
  echo "Administrator Account Configuration"
  echo "-----------------------------------"
  echo "Configure the administrator account for SCLAB Studio."
  echo ""
  read -r -p "Admin email address [Enter = admin@sclab.io]: " ADMIN_EMAIL || true
  if [ -n "${ADMIN_EMAIL:-}" ]; then
    echo " → Admin email set to: $ADMIN_EMAIL"
  else
    ADMIN_EMAIL="admin@sclab.io"
    echo " → Using default admin email: $ADMIN_EMAIL"
  fi
  
  echo ""
  echo "Admin password configuration:"
  echo "You can either enter your own password or press Enter to auto-generate a secure one."
  read_password "Admin password [Enter = auto-generate]: " ADMIN_PASSWORD
  if [ -n "${ADMIN_PASSWORD:-}" ]; then
    echo " → Using your custom admin password."
  else
    ADMIN_PASSWORD="$(gen_secret)"
    echo " → Auto-generated secure admin password."
  fi
  
  echo ""
  echo "========================================"
  echo "Applying Configuration"
  echo "========================================"
  
  # Replace secrets
  do_replace_all "changeThisMongoPassword"  "$MONGO_PW"   "MongoDB password"
  do_replace_all "changeThisRedisPassword"  "$REDIS_PW"   "Redis password"
  do_replace_all "changeThisQdrantApiKey"   "$QDRANT_KEY" "Qdrant API key"
  
  # Replace OpenAI API key
  OPENAI_REPLACEMENT="${OPENAI_KEY:-}"
  do_replace_all "openAiApiKeyHere" "$OPENAI_REPLACEMENT" "OpenAI API key"
  # Replace Gemini API key
  GEMINI_REPLACEMENT="${GEMINI_API_KEY:-}"
  do_replace_all "geminiApiKeyHere" "$GEMINI_REPLACEMENT" "Gemini API key"
  
  # Update AI configuration based on provided API keys
  if [ -n "${OPENAI_KEY:-}" ]; then
    echo " - Updating settings.json for OpenAI configuration..."
    if [ -f "settings.json" ]; then
      safe_sed_inplace "settings.json" '"sqlModel"[[:space:]]*:[[:space:]]*"[^"]*"' '"sqlModel": "GPT5_MINI"'
      safe_sed_inplace "settings.json" '"llmAPI"[[:space:]]*:[[:space:]]*"[^"]*"' '"llmAPI": "openai"'
      echo " - settings.json: updated sqlModel to 'GPT5_MINI' and hub.llmAPI to 'openai'."
    else
      echo " ! Warning: settings.json not found; could not update AI configuration."
    fi
  elif [ -n "${GEMINI_API_KEY:-}" ]; then
    echo " - Updating settings.json for Gemini configuration..."
    if [ -f "settings.json" ]; then
      safe_sed_inplace "settings.json" '"sqlModel"[[:space:]]*:[[:space:]]*"[^"]*"' '"sqlModel": "GEMINI_gemini-3-pro-preview"'
      safe_sed_inplace "settings.json" '"llmAPI"[[:space:]]*:[[:space:]]*"[^"]*"' '"llmAPI": "gemini"'
      echo " - settings.json: updated sqlModel to 'GEMINI_gemini-3-pro-preview' and hub.llmAPI to 'gemini'."
    else
      echo " ! Warning: settings.json not found; could not update AI configuration."
    fi
  fi
  
  # Replace domain
  if [ -n "${DOMAIN_NEW:-}" ]; then
    do_replace_domain_only "yourdomain.com" "$DOMAIN_NEW" "domain" "yourdomain\\.com"
  fi
  
  # Update mainPrefix
  if [ -f "settings.json" ]; then
    echo " - Updating mainPrefix in settings.json..."
    # Escape special characters for JSON
    MAIN_PREFIX_JSON=$(printf '%s' "${MAIN_PREFIX:-}" | sed 's/["\]/\\&/g')
    
    # Use temporary file for replacement
    cp settings.json settings.json.tmp
    sed 's/"mainPrefix"[[:space:]]*:[[:space:]]*"[^"]*"/"mainPrefix": "'"$MAIN_PREFIX_JSON"'"/g' settings.json.tmp > settings.json
    rm -f settings.json.tmp
    
    echo " - settings.json: updated mainPrefix to '${MAIN_PREFIX:-}'"
  else
    echo " ! Warning: settings.json not found; could not update mainPrefix."
  fi
  
  # Replace license
  do_replace_license_only "$LICENSE_PLACEHOLDER" "$LICENSE_KEY" "license key"
  
  # Update admin credentials
  if [ -f "settings.json" ]; then
    echo " - Updating administrator credentials in settings.json..."
    # Escape special characters for JSON
    ADMIN_EMAIL_JSON=$(printf '%s' "$ADMIN_EMAIL" | sed 's/["\]/\\&/g')
    ADMIN_PASSWORD_JSON=$(printf '%s' "$ADMIN_PASSWORD" | sed 's/["\]/\\&/g')
    
    # Use a different approach for complex replacements
    cp settings.json settings.json.tmp
    sed 's/"adminEmail"[[:space:]]*:[[:space:]]*"[^"]*"/"adminEmail": "'"$ADMIN_EMAIL_JSON"'"/g' settings.json.tmp > settings.json.tmp2
    sed 's/"adminPassword"[[:space:]]*:[[:space:]]*"[^"]*"/"adminPassword": "'"$ADMIN_PASSWORD_JSON"'"/g' settings.json.tmp2 > settings.json
    rm -f settings.json.tmp settings.json.tmp2
    
    echo " - settings.json: updated admin credentials"
  else
    echo " ! Warning: settings.json not found; could not update admin credentials."
  fi

  # Create log folder
  mkdir -p ./data/logs
  
  # Create .init file
  umask 077
  {
    echo "initialized_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
    echo "files=${FILES[*]}"
    echo "domain_files=${DOMAIN_FILES[*]}"
    echo "license_file=$LICENSE_FILE"
    echo "distro=$DISTRO_ID"
    echo "arch=$ARCH_NORMALIZED"
  } > "$INIT_FILE"
  
  echo ""
  echo "✅ Configuration completed successfully!"
  echo ""
  echo "Configuration has been saved. To reconfigure, delete the .init file and run this script again."
  
  # Generate security keys
  echo ""
  echo "Generating security keys..."
  echo "Creating JWT tokens and SSL certificates for secure communication..."
  $DOCKER_COMPOSE -f gen.yml run --rm key-generator
  
  # Create Docker network
  echo ""
  echo "Creating Docker network..."
  echo "Setting up internal network for container communication..."
  docker network create sclab-network 2>/dev/null || true
  
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
  if [ -n "${DOMAIN_NEW:-}" ]; then
    echo "  - Main site: https://$DOMAIN_NEW"
    if [ -n "${MAIN_PREFIX:-}" ]; then
      echo "  - Editor: https://$MAIN_PREFIX.$DOMAIN_NEW"
    fi
  else
    echo "  - https://127.0.0.1 (update domain for production use)"
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
}

# Run main function
main "$@"
