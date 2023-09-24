#!/usr/bin/env bash
export METEOR_SETTINGS=$(cat ./settings.json)
docker compose pull
PREVIOUS_CONTAINER=$(docker ps --format "table {{.ID}}  {{.Names}}  {{.CreatedAt}}" | grep webapp | awk -F  "  " '{print $1}')
docker compose up -d --no-deps --scale webapp=2 --no-recreate webapp
echo "Wait for 30 seconds for the startup"
sleep 30
docker kill -s SIGTERM $PREVIOUS_CONTAINER
sleep 1
docker rm -f $PREVIOUS_CONTAINER
docker compose up -d --no-deps --scale webapp=1 --no-recreate webapp
docker compose stop sclab-proxy 
docker compose up -d --no-deps --build sclab-proxy