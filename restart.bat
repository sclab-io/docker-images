@echo off
docker compose down
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 873379329511.dkr.ecr.ap-northeast-2.amazonaws.com

powershell -NoProfile -Command "$env:METEOR_SETTINGS = ((Get-Content -Raw -Path 'settings.json') -replace '(\r?\n)+',' ').Trim(); docker compose up -d --remove-orphans"