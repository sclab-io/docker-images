#!/usr/bin/env bash
# HTML → PDF 변환 서비스(Gotenberg)를 켠다. 안전하게 여러 번 실행할 수 있다(이미 있으면 설정값만 다시 쓴다).
#   1. docker-compose.yml 에 gotenberg 서비스를 추가한다.
#   2. gotenberg.env 에 사이트 도메인(<siteCode>.<도메인>)을 sclab-proxy 로 연결하는 규칙을 쓴다.
#   3. ai-service.env 에 GOTENBERG_URL / HTML_TO_PDF_PUBLIC_URL 을 쓴다.
# install.sh 가 설치를 선택했을 때 호출하며, 나중에 직접 실행해도 된다(도메인을 바꾼 뒤에도 다시 실행).
# 적용: ./run.sh (또는 ./update.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
COMPOSE=docker-compose.yml
SNIPPET=gotenberg/docker-compose.gotenberg.yml
COMMON_ENV=common.env
GOTENBERG_ENV=gotenberg.env
AI_ENV=ai-service.env

for f in "$COMPOSE" "$SNIPPET" "$COMMON_ENV" "$AI_ENV"; do
  [ -f "$f" ] || { echo "[Error] $f not found." >&2; exit 1; }
done

# KEY=value 를 env 파일에 쓴다(있으면 교체, 없으면 끝에 추가). 값에 특수문자가 있어도 안전하도록 awk 를 쓴다.
set_env_value() {
  local file="$1" key="$2" value="$3" tmp
  [ -f "$file" ] || : > "$file"
  # 마지막 줄에 개행이 없으면 붙인다
  if [ -s "$file" ] && [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then echo >> "$file"; fi
  tmp=$(mktemp "${file}.XXXXXX")
  KEY="$key" VALUE="$value" awk '
    BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"]; done = 0 }
    index($0, k "=") == 1 { if (!done) { print k "=" v; done = 1 }; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# 사이트 주소(ROOT_URL)에서 호스트 이름을 뽑는다. 예) https://sclab.example.com:443/ → sclab.example.com
ROOT_URL="$(grep -E '^ROOT_URL=' "$COMMON_ENV" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r')"
[ -n "$ROOT_URL" ] || { echo "[Error] ROOT_URL not found in $COMMON_ENV." >&2; exit 1; }
HOST_PART="${ROOT_URL#*://}"
HOST_PART="${HOST_PART%%/*}"
DOMAIN="${HOST_PART%%:*}"
[ -n "$DOMAIN" ] || { echo "[Error] could not read the domain from ROOT_URL ($ROOT_URL)." >&2; exit 1; }

# 1. docker-compose.yml 에 서비스 추가
if grep -qE '^  gotenberg:' "$COMPOSE"; then
  echo " - $COMPOSE: gotenberg service already present."
else
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
  echo " - $COMPOSE: added gotenberg service."
fi

# 2. 사이트 도메인을 프록시로 연결(컨테이너 안에서 <siteCode>.<도메인> 을 열 수 있게)
set_env_value "$GOTENBERG_ENV" CHROMIUM_HOST_RESOLVER_RULES "MAP *.${DOMAIN} sclab-proxy, MAP ${DOMAIN} sclab-proxy"
set_env_value "$GOTENBERG_ENV" CHROMIUM_IGNORE_CERTIFICATE_ERRORS "true"
echo " - $GOTENBERG_ENV: site domain '$DOMAIN' is mapped to sclab-proxy."

# 3. ai-service 가 Gotenberg 를 호출하고 사이트 주소를 만들 수 있게
set_env_value "$AI_ENV" GOTENBERG_URL "http://gotenberg:3000"
set_env_value "$AI_ENV" HTML_TO_PDF_PUBLIC_URL "$ROOT_URL"
echo " - $AI_ENV: GOTENBERG_URL=http://gotenberg:3000, HTML_TO_PDF_PUBLIC_URL=$ROOT_URL"
echo "   Apply with ./run.sh (the HTML to PDF block needs the site to be published)."
