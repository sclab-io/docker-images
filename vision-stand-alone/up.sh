#!/usr/bin/env bash
# 시작. 예: ./up.sh   (특정 서비스: ./up.sh vision-aio)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_tls.sh
ensure_tls_cert
. ./_dc.sh
exec ${DC} up -d "$@"
