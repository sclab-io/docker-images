#!/usr/bin/env bash
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 873379329511.dkr.ecr.ap-northeast-2.amazonaws.com

export METEOR_SETTINGS=$(cat ./settings.json)
docker compose up -d
docker compose up -d --no-deps --scale webapp=10 --no-recreate webapp