#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_tls.sh
ensure_tls_cert
. ./_dc.sh
${DC} down
exec ${DC} up -d "$@"
