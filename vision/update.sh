#!/usr/bin/env bash
# 업데이트: 최신 이미지를 가져온 뒤 컨테이너를 다시 생성한다. ECR 레지스트리는 먼저 docker login이 필요하다.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
${DC} pull
${DC} up -d
echo "Update complete"
