# 공통(source 전용): DC 변수에 올바른 docker compose 명령을 설정한다(sudo 필요 시 자동).
# .env의 COMPOSE_FILE(gpu 오버레이)·COMPOSE_PROFILES(db/s3)는 docker compose가 알아서 읽는다.
SUDO=""
if ! docker info >/dev/null 2>&1; then
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then SUDO="sudo "
  else echo "docker 데몬에 접근할 수 없습니다(데몬 실행/권한 확인)." >&2; return 1 2>/dev/null || exit 1; fi
fi
if ${SUDO}docker compose version >/dev/null 2>&1; then DC="${SUDO}docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="${SUDO}docker-compose"
else echo "docker compose(플러그인) 또는 docker-compose가 필요합니다." >&2; return 1 2>/dev/null || exit 1; fi
