#!/usr/bin/env bash
export METEOR_SETTINGS=$(cat ./settings.json)
docker compose logs > ./data/logs/sclab-compose-logs-$(date +%F_%H%M).log
docker compose stop
