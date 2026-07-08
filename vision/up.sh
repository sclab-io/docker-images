#!/usr/bin/env bash
# 시작. 예: ./up.sh   (특정 서비스: ./up.sh vision-aio)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
mkdir -p data/vision/app data/vision/recordings
chmod 0777 data/vision/app data/vision/recordings
. ./_dc.sh
echo "Starting SCLAB Vision..."
${DC} up -d --remove-orphans "$@"
echo "SCLAB Vision started."
