#!/usr/bin/env bash
# Stop and remove containers while keeping data. ./down.sh -v also removes named volumes; ./data/vision bind mounts remain.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
exec ${DC} down "$@"
