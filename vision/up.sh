#!/usr/bin/env bash
# Start. Example: ./up.sh   (specific service: ./up.sh vision-aio)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} up -d "$@"
