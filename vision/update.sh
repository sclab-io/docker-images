#!/usr/bin/env bash
# 업데이트: 최신 이미지 pull 후 롤링 재기동. (ECR이면 사전 docker login 필요)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
${DC} pull
${DC} up -d
echo "✓ 업데이트 완료"
