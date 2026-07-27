#!/usr/bin/env bash
# 최신 이미지를 가져온다. 이후 ./up.sh를 실행해 반영한다.
# ECR 토큰은 12시간이면 만료되므로 pull 직전에 항상 재로그인한다(_ecr.sh).
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh
. ./_ecr.sh
ecr_login
exec ${DC} pull "$@"
