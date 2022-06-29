#!/usr/bin/env bash
export METEOR_SETTINGS=$(cat ./settings.json)
docker compose up -d
