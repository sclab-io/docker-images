#!/usr/bin/env bash
# 데이터를 유지하면서 컨테이너를 중지하고 제거한다. ./down.sh -v는 named volume도 제거하지만 ./data/vision bind mount는 유지된다.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} down "$@"
