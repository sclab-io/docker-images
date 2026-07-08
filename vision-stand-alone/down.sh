#!/usr/bin/env bash
# ./data 아래 bind mount 데이터를 유지하면서 컨테이너를 중지하고 제거한다.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} down "$@"
