#!/usr/bin/env bash
if [ -f .offline ]; then
  echo "[offline] This is an offline installation: images come from the offline bundle (docker load). Nothing to pull."
  exit 0
fi
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 873379329511.dkr.ecr.ap-northeast-2.amazonaws.com
docker compose pull