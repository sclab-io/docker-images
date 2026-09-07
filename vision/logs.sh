#!/usr/bin/env bash
# 로그 팔로우. 예: ./logs.sh   (특정 서비스: ./logs.sh vision-aio)
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"
. ./_dc.sh

# 이 디렉터리의 compose 프로젝트명(.env COMPOSE_PROJECT_NAME, 없으면 디렉터리명).
project_name() {
  local p=""
  [ -f .env ] && p="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' .env | tail -1)"
  p="${COMPOSE_PROJECT_NAME:-$p}"
  echo "${p:-$(basename "$PWD")}"
}

# compose logs는 현재 프로젝트 라벨이 붙은 컨테이너만 찾는다. 컨테이너가 다른 프로젝트/디렉터리에서
# 기동됐으면 "Attaching to"만 찍고 조용히 끝나므로, 먼저 확인하고 원인을 안내한다.
show_logs() {
  if [ -z "$(${DC} ps -q "$@" 2>/dev/null || true)" ]; then
    local project; project="$(project_name)"
    echo "No running containers for compose project '${project}' (service: ${*:-all}) in $PWD." >&2
    echo "Compose-managed containers on this host:" >&2
    ${SUDO}docker ps -a --filter label=com.docker.compose.project \
      --format 'table {{.Names}}\t{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}\t{{.Status}}' >&2
    echo "Hint: run logs.sh from the WORKING_DIR that started the containers, or set COMPOSE_PROJECT_NAME in .env to that PROJECT." >&2
    echo "      For a single container: ${SUDO}docker logs -f --tail=200 <container-name>" >&2
    exit 1
  fi
  exec ${DC} logs -f --tail=200 "$@"
}

if [ $# -gt 0 ]; then
  show_logs "$@"
fi

echo "Display logs"
echo "-------------------"
echo "all"
echo "vision-aio"
echo "vision-console"
echo "vision-tls"
echo "rustfs"
echo "-------------------"
read -p "Choose service [all]: " runEnv
runEnv=${runEnv:-all}

if [ "$runEnv" = "all" ]; then
  show_logs
else
  show_logs "$runEnv"
fi
