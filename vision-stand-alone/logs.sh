#!/usr/bin/env bash
# 로그 팔로우. 예: ./logs.sh vision-aio
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} logs -f --tail=200 "$@"
