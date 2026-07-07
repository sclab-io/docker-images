#!/usr/bin/env bash
# 중지(컨테이너 제거, 데이터/볼륨 유지). 완전 삭제는 ./down.sh -v (주의: ./data/vision는 바인드마운트라 유지됨).
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} down "$@"
