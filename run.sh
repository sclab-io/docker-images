#!/usr/bin/env bash
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 873379329511.dkr.ecr.ap-northeast-2.amazonaws.com

. ./_tls.sh
ensure_tls_cert

export METEOR_SETTINGS=$(cat ./settings.json)
docker compose up -d --remove-orphans
