# 공통 헬퍼: 프라이빗 ECR 로그인.
#
# ECR 인증 토큰은 **12시간 뒤 만료**된다. 설치 당시엔 install.sh가 로그인해 두지만, 하루 뒤 ./pull.sh를
# 실행하면 "authorization token has expired"로 pull이 실패한다. 그래서 pull 경로(pull.sh/update.sh)가
# 매번 이 헬퍼로 재로그인한다(토큰이 아직 살아 있어도 재발급은 몇 초면 끝난다).
#
# 사용: `. ./_ecr.sh` 후 `ecr_login`  (레지스트리는 인자 > 환경변수 > .env 순으로 결정)
# 레지스트리가 ECR이 아니거나 aws CLI가 없으면 조용히(경고만) 건너뛴다 — 로컬 이미지로 계속 진행 가능.

# .env에서 값을 읽는다(주석·따옴표 제거). 없으면 빈 문자열.
_ecr_env_value() {
  [ -f .env ] || return 0
  sed -n "s/^[[:space:]]*$1=//p" .env | tail -1 | sed 's/[[:space:]]*#.*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/'
}

# ECR 레지스트리면 docker login. 그 외에는 no-op(0 반환).
# $1 = 레지스트리 주소(생략 시 $VISION_REGISTRY 또는 .env의 VISION_REGISTRY)
ecr_login() {
  local registry region host
  registry="${1:-${VISION_REGISTRY:-$(_ecr_env_value VISION_REGISTRY)}}"
  case "$registry" in
    *.dkr.ecr.*.amazonaws.com*) ;;
    *) return 0 ;;  # ECR이 아니면 로그인 불필요
  esac
  region="$(printf '%s' "$registry" | sed -n 's/.*\.dkr\.ecr\.\([a-z0-9-]*\)\.amazonaws\.com.*/\1/p')"
  host="$(printf '%s' "$registry" | sed -n 's#\(^[0-9]*\.dkr\.ecr\.[a-z0-9-]*\.amazonaws\.com\).*#\1#p')"
  if ! command -v aws >/dev/null 2>&1; then
    echo "WARN: aws CLI not found — skipping ECR login. Private image pull will fail." >&2
    echo "      Install it, then: aws configure   (or re-run ./install.sh)" >&2
    return 0
  fi
  echo "Logging in to ECR (${host})..."
  # 토큰 발급: 현재 사용자 → 실패 시 sudo 폴백(자격증명을 `sudo aws configure`로 root에만 넣은 호스트 —
  # docker는 ${SUDO}로 sudo를 붙이면서 aws만 일반 사용자로 돌면 로그인이 항상 실패한다).
  local pw=""
  pw="$(aws ecr get-login-password --region "$region" 2>/dev/null)" || true
  if [ -z "$pw" ] && command -v sudo >/dev/null 2>&1; then
    pw="$(sudo aws ecr get-login-password --region "$region" 2>/dev/null)" || true
  fi
  if [ -n "$pw" ] && printf '%s' "$pw" \
      | ${SUDO:-}docker login --username AWS --password-stdin "$host" >/dev/null 2>&1; then
    echo "ECR login OK"
  else
    echo "WARN: ECR login failed — check AWS credentials (aws configure / SSO / instance role)." >&2
    echo "      Manual: sudo aws ecr get-login-password --region ${region} | ${SUDO:-}docker login --username AWS --password-stdin ${host}" >&2
  fi
}
