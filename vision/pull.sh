#!/usr/bin/env bash
# 최신 이미지 pull(업데이트 전 실행). 이후 ./up.sh 로 롤링 반영.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} pull "$@"
