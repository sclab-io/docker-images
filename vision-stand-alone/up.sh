#!/usr/bin/env bash
# 시작. 예: ./up.sh   (특정 서비스: ./up.sh vision-aio)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
chmod_data_dirs() {
  chmod 0777 "$@" 2>/dev/null && return 0
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo chmod 0777 "$@"
  else
    return 1
  fi
}
. ./_tls.sh
ensure_tls_cert
mkdir -p data/vision/app data/vision/recordings
DATA_DIRS=(data/vision/app data/vision/recordings)
PROFILES="${COMPOSE_PROFILES:-}"
if [ -f .env ]; then
  ENV_PROFILES="$(sed -n 's/^COMPOSE_PROFILES=//p' .env | tail -1)"
  PROFILES="${PROFILES:-$ENV_PROFILES}"
fi
case ",${PROFILES}," in
  *,s3,*) mkdir -p data/vision/rustfs data/vision/rustfs-logs; DATA_DIRS+=(data/vision/rustfs data/vision/rustfs-logs) ;;
esac
chmod_data_dirs "${DATA_DIRS[@]}"
. ./_dc.sh
echo "Starting SCLAB Vision stand-alone..."
${DC} up -d --remove-orphans "$@"
echo "SCLAB Vision stand-alone started."
