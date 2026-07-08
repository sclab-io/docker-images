#!/usr/bin/env bash
# 공통 헬퍼. 필요하면 sudo를 포함해 올바른 docker compose 명령을 DC에 설정한다.
# docker compose는 이 디렉터리의 .env를 자동으로 읽는다.
SUDO=""
if ! docker info >/dev/null 2>&1; then
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    SUDO="sudo "
  else
    echo "Cannot access the Docker daemon. Check daemon status and permissions." >&2
    return 1 2>/dev/null || exit 1
  fi
fi

if ${SUDO}docker compose version >/dev/null 2>&1; then
  DC="${SUDO}docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="${SUDO}docker-compose"
else
  echo "docker compose plugin or docker-compose is required." >&2
  return 1 2>/dev/null || exit 1
fi
