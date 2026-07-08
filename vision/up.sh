#!/usr/bin/env bash
# 시작. 예: ./up.sh   (특정 서비스: ./up.sh vision-aio)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
mkdir -p data/vision/app data/vision/recordings
DATA_DIRS=(data/vision/app data/vision/recordings)
if [ -f .env ]; then
  PROFILES="$(sed -n 's/^COMPOSE_PROFILES=//p' .env | tail -1)"
  case ",${PROFILES}," in
    *,s3,*) mkdir -p data/vision/rustfs; DATA_DIRS+=(data/vision/rustfs) ;;
  esac
fi
chmod 0777 "${DATA_DIRS[@]}"
. ./_dc.sh
echo "Starting SCLAB Vision..."
${DC} up -d --remove-orphans "$@"
echo "SCLAB Vision started."
