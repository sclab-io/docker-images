@echo off
powershell -NoProfile -Command "$env:METEOR_SETTINGS = ((Get-Content -Raw -Path 'settings.json') -replace '(\r?\n)+',' ').Trim(); docker compose up -d"

aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 873379329511.dkr.ecr.ap-northeast-2.amazonaws.com

setlocal enabledelayedexpansion

REM 1. Docker Compose 이미지 업데이트
docker compose pull

REM 2. docker ps 명령의 출력에서 "webapp"이 포함된 행의 첫 번째 토큰(컨테이너 ID) 추출
for /f "skip=1 tokens=1" %%i in ('docker ps --format "table {{.ID}}  {{.Names}}  {{.CreatedAt}}" ^| findstr /I "webapp"') do (
    set "PREVIOUS_CONTAINER=%%i"
)

REM 추출된 컨테이너 ID 출력 (디버그용)
echo Previous container: !PREVIOUS_CONTAINER!

REM 3. webapp 서비스를 스케일업(컨테이너 2개 실행, 재생성 없이)
docker compose up -d --no-deps --scale webapp=2 --no-recreate webapp

echo Wait for 30 seconds for the startup
timeout /t 30 /nobreak >nul

REM 4. 이전 컨테이너에 SIGTERM 전송 후 종료
docker kill -s SIGTERM !PREVIOUS_CONTAINER!
timeout /t 1 /nobreak >nul
docker rm -f !PREVIOUS_CONTAINER!

REM 5. webapp 서비스를 스케일다운(컨테이너 1개 실행, 재생성 없이)
docker compose up -d --no-deps --scale webapp=1 --no-recreate webapp

REM 6. sclab-proxy 서비스 중지 후 재빌드하여 실행
docker compose stop sclab-proxy 
docker compose up -d --no-deps --build sclab-proxy

endlocal