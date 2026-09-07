#!/usr/bin/env bash
# docker-compose.yml 에 타일 서버 서비스(tileserver, tileserver-edge)를 추가한다. 이미 있으면 아무것도 하지 않는다.
# install.sh 가 타일 서버 설치를 선택했을 때 호출하며, 나중에 직접 실행해도 된다.
set -euo pipefail
cd "$(dirname "$0")/.."
COMPOSE=docker-compose.yml
SNIPPET=tileserver/docker-compose.tileserver.yml

if grep -qE '^  tileserver:' "$COMPOSE"; then
  echo " - $COMPOSE: tile server services already present."
  exit 0
fi
grep -qE '^networks:' "$COMPOSE" || { echo "[Error] 'networks:' section not found in $COMPOSE" >&2; exit 1; }

# 주석(#) 줄을 뺀 스니펫을 최상위 networks: 바로 앞(services 블록 끝)에 끼워 넣는다.
cp "$COMPOSE" "$COMPOSE.bak"
awk -v snippet="$SNIPPET" '
  /^networks:/ && !done {
    while ((getline line < snippet) > 0) { if (line !~ /^#/) print line }
    close(snippet)
    print ""
    done = 1
  }
  { print }
' "$COMPOSE.bak" > "$COMPOSE"
rm -f "$COMPOSE.bak"
echo " - $COMPOSE: added tile server services (tileserver, tileserver-edge)."
