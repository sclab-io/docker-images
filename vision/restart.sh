#!/usr/bin/env bash
# 재시작. 예: ./restart.sh   (특정 서비스: ./restart.sh vision-console)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} restart "$@"
