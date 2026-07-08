#!/usr/bin/env bash
# 로그 팔로우. 예: ./logs.sh   (특정 서비스: ./logs.sh vision-aio)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh

if [ $# -gt 0 ]; then
  exec ${DC} logs -f --tail=200 "$@"
fi

echo "Display logs"
echo "-------------------"
echo "all"
echo "vision-aio"
echo "vision-console"
echo "rustfs"
echo "-------------------"
read -p "Choose service [all]: " runEnv
runEnv=${runEnv:-all}

if [ "$runEnv" = "all" ]; then
  exec ${DC} logs -f --tail=200
else
  exec ${DC} logs -f --tail=200 "$runEnv"
fi
