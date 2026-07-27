#!/usr/bin/env bash
# 업데이트: 최신 이미지를 가져온 뒤 컨테이너를 다시 생성한다. ECR 로그인은 _ecr.sh가 자동 처리한다.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
. ./_ecr.sh
ecr_login
${DC} pull
${DC} up -d
echo "Update complete"
