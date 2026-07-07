#!/usr/bin/env bash
# Update: pull latest images, then recreate containers. ECR registries require docker login first.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
${DC} pull
${DC} up -d
echo "✓ 업데이트 완료"
