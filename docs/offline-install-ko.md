# 폐쇄망(오프라인) 설치 가이드

> English version: [offline-install.md](offline-install.md) · [README](../README-ko.md) 로 돌아가기

이 문서는 **인터넷이 전혀 없는** 서버(Docker 저장소, GitHub, AWS/ECR 모두 접속 불가)에 SCLAB Studio 를 설치하는 방법입니다.
서버에 필요한 모든 것 - Docker Engine, Docker Compose, 모든 컨테이너 이미지, 이 저장소의 파일, 라이선스 키 - 을
**인터넷이 되는** 머신에서 분할 파일 몇 개로 묶어 두고, 그 파일을 서버로 옮겨 스크립트 하나만 실행합니다.

```
 인터넷이 되는 PC / 서버                           폐쇄망 서버
 ───────────────────────────                       ───────────────────────────
 ./make-offline-zip.sh   ──►  *.tar.gz[.part*] ──►   sudo bash ./install-offline.sh
   (이미지 pull, Docker,       SHA256SUMS            (검증, 압축 해제, Docker 설치,
    라이선스, 분할/비분할)        MANIFEST.json          docker load, install.sh, 기동)
                               install-offline.sh
```

## 1. 개요

| 스크립트 | 실행 위치 | 하는 일 |
|---|---|---|
| `make-offline-zip.sh` | 인터넷이 되는 머신(모든 Linux) | 대상 OS/아키텍처와 서비스를 고르게 하고, AWS CLI 가 없으면 설치하고, ECR 에 로그인하고, Docker Engine + Compose 를 내려받고, 선택한 모든 이미지를 `docker pull` + `docker save` 한 뒤, 라이선스 키와 함께 하나의 압축 파일로 묶고(기본 1GB 단위 분할, 분할 안 함 / GB / MB 단위 선택 가능) `SHA256SUMS`, `MANIFEST.json` 을 만듭니다 |
| `install-offline.sh` | 폐쇄망 서버(root) | 체크섬을 검증하고, 분할 파일을 합쳐 압축을 풀고, 번들의 Docker + Compose 를 설치하고(이미 Docker 가 있으면 건너뜀), 이미지를 `docker load` 하고, `install.sh --offline` 을 실행(라이선스는 번들에서 자동 적용)한 뒤 서비스를 기동합니다 |
| `make-offline-update-zip.sh` | 인터넷이 되는 머신(Linux 또는 macOS) | 고른 이미지(예: `webapp`)만 담은 작은 **업데이트 번들**을 만듭니다 - 8절 참고 |
| `update-offline-images.sh` | 폐쇄망 서버(root) | 업데이트 번들을 검증·적재하고 설치된 시스템에 적용합니다(`webapp` 롤링 업데이트, 헬스 확인, 롤백, 이력) - 8절 참고 |

설계 메모

- **Docker 는 정적 바이너리**(`download.docker.com/linux/static`)로 설치합니다. `.deb`/`.rpm` 패키지는 배포판 버전별 의존성
  (containerd.io, iptables, container-selinux 등)이 있어 OS 저장소 없이는 해결할 수 없지만, 정적 tgz 는 CPU 아키텍처별로 완결된
  바이너리 묶음이라 어떤 배포판에서도 동작합니다. 메뉴에서 고르는 OS 계열은 서비스 관리자(systemd / OpenRC) 선택과 경고 안내에만 쓰입니다.
- **이미지는 받은 그대로 고정**됩니다. 모든 이미지를 `docker save` 하고, `MANIFEST.json` 에 이미지별 태그/이미지 ID/repo digest 를 기록합니다.
  번들 안의 compose 파일에는 `pull_policy: never` 가 들어가 항상 적재된 이미지를 쓰고 레지스트리에 접속하지 않습니다(`latest` 태그는 "번들에 담긴 그 이미지"를 뜻합니다).
- 서버에서는 AWS CLI, ECR 로그인, `docker compose pull`, Docker/Compose 다운로드, `git` 을 **전혀 사용하지 않습니다**.

## 2. 준비물

인터넷이 되는 머신(Linux 또는 macOS Intel/Apple Silicon - "Mac 에서 번들 만들기" 참고):

- `bash`, `tar`, `gzip`, `split`, `sha256sum`, `curl` 또는 `wget`, Docker (없으면 OS 패키지 관리자로 설치할지 물어봅니다)
- SCLAB ECR 레지스트리용 AWS 자격 증명(SCLAB 지원팀 제공) - ECR 이미지를 받을 때만 필요, AWS CLI 는 없으면 자동 설치
- SCLAB **라이선스 키**(문자열. 설치 시 `settings.json` 의 `private.license` 에 들어갑니다)
- 여유 디스크: 전체 이미지 크기의 **약 2.5배** (필수 서비스만 약 1.5GB, 타일 서버만 약 95GB)

폐쇄망 서버(root 권한):

- **x86_64(amd64)** 또는 **aarch64(arm64)** Linux - 번들을 만들 때 고른 CPU 아키텍처와 같아야 함, `bash`, `tar`, `gzip`, `sha256sum`, `openssl`, `awk`, `sed`, `grep`, `iptables` 또는 `nftables`
- 여유 디스크: 번들 크기(압축 해제) **+** 이미지 크기(Docker 데이터 디렉터리, 보통 `/var/lib/docker`)

## 3. 1단계 - 번들 만들기 (인터넷이 되는 머신)

```bash
git clone https://github.com/sclab-io/docker-images.git
cd docker-images
./make-offline-zip.sh
```

대화식으로 진행됩니다.

1. **대상 OS 계열** (화살표 메뉴: ↑/↓ 또는 `j`/`k` 이동, Enter 선택).
2. 서버의 **대상 CPU 아키텍처**: `x86_64 (amd64)`(기본값) 또는 `aarch64 (arm64)`. 둘 다 지원합니다. 일부 선택 서비스는 **x86_64 전용**입니다 -
   GPU(`vision-gpu`, 이미지 `vision-aio-gpu`)와 일부 서드파티 이미지(예: `ollama` ROCm 변형). aarch64 번들에 이런 서비스를 고르면
   스크립트가 해당 서비스를 알려 주고 아무것도 내려받기 전에 중단하므로, 선택에서 빼고 다시 실행하세요.
3. **서비스 선택** - 체크박스 메뉴. ↑/↓(또는 `j`/`k`)로 이동, **Space** 로 토글, `a` = 전체, `n` = 없음, **Enter** = 계속.
   필수 서비스는 잠금 표시되며 해제할 수 없습니다. 터미널이 아닐 때(파이프/CI)나 `TERM=dumb` 에서는 번호 입력 방식으로 자동 전환됩니다.
   `mongo redis webapp sclab-proxy mail` 은 항상 포함됩니다. 선택 항목: `qdrant ai-service node-vm-service sclab-agent gis-process
   mqtt-client mqtt-broker kafka-client tileserver gotenberg vision vision-gpu ollama vllm speaches`.
   선택하지 않은 서비스는 이미지를 받지 않고 번들의 `docker-compose.yml` 에서도 빠집니다.
4. **라이선스 키**(입력 숨김) - 번들 안 `license/LICENSE.key`(권한 600)로 저장되고 서버에서 자동 적용됩니다.
5. 필요하면 AWS CLI 설치 / `aws configure` / ECR 로그인, 이어서 pull, save, 압축, 분할.

비대화식 예:

```bash
./make-offline-zip.sh --yes --os ubuntu --arch x86_64 \
  --services qdrant,ai-service,node-vm-service,gotenberg \
  --license-file ./my-license.txt --out ./sclab-offline-out
```

전체 옵션은 `./make-offline-zip.sh --help` (`--list-services` 로 서비스 목록 확인, `--no-split`, `--part-size 5G|500M`, `--no-license`,
`--docker-version`, `--compose-version`, `--work-dir`, 로컬에 이미 있는 이미지를 쓰는 `--no-pull`).

**분할 방식.** 기본값은 아카이브를 1GB 단위(`*.tar.gz.part001`, `.part002`, ...)로 나누는 것입니다. USB 디스크나 용량 제한이 있는
전송 도구로 옮길 때 편합니다. 대화식으로 실행하면 분할 방식을 묻습니다. *분할 안 함*(하나의 파일), *GB 단위로 분할*(`Part size in GB [1]` 입력),
*MB 단위로 분할*(`Part size in MB [1024]` 입력) 중에서 고르며, Enter 만 누르면 기본값(1GB 단위)입니다. 크기는 정수(최소 1MB)로 입력합니다.
분할 크기가 번들 전체보다 크면 분할하지 않은 것과 같이 하나의 파일이 만들어집니다. 터미널이 없거나 `--yes` 이면 옵션을 주지 않는 한 기본 1GB 입니다.

```bash
./make-offline-zip.sh --no-split            # 하나의 파일: sclab-offline-<날짜>-<arch>.tar.gz
./make-offline-zip.sh --part-size 5G        # 5GB 단위 분할
./make-offline-zip.sh --part-size 500M      # 500MB 단위 분할 (1024 처럼 단위 없는 숫자는 MB)
```

`--no-split` 과 `--part-size` 는 함께 쓸 수 없습니다. `install-offline.sh` 는 하나의 파일도, 분할 파일도 모두 처리합니다.

### Mac(Intel / Apple Silicon)에서 번들 만들기

`make-offline-zip.sh` 는 macOS 에서도 실행됩니다(번들은 항상 **Linux** 서버용이며 `install-offline.sh` 는 Linux 전용입니다).

- 준비물: 실행 중인 Docker 엔진(**Docker Desktop**, **OrbStack**, **Colima**), Homebrew(선택, AWS CLI 설치에 사용), macOS 기본 도구
  (기본 bash 3.2 와 BSD 도구로 동작). AWS CLI 가 없으면 자동 설치합니다: `brew install awscli`, 없으면 공식 설치 프로그램을 현재 사용자 전용(`~/.local/aws-cli`, sudo 불필요)으로 설치합니다.
- **대상**은 메뉴 / `--os` / `--arch` 로 고른 서버이며 Mac 의 CPU 가 아닙니다. Apple Silicon 에서도 메뉴 기본값은 x86_64 이며, arm64 서버용이면 aarch64 를 고르세요.
  이미지는 `docker pull --platform linux/amd64`(또는 `linux/arm64`)로 받아 `docker save --platform ...` 로 저장하며, 다른 아키텍처 코드는 실행하지 않습니다(에뮬레이션 없음).
  서버용 Docker Engine tgz 와 Compose 바이너리는 번들에 **내려받기만** 하고 Mac 에는 설치하지 않습니다.
- 이미지는 로컬 Docker 엔진에 pull 되어 같은 이름의 로컬 태그를 바꿉니다. 엔진에 같은 태그의 다른 아키텍처 이미지(예: 직접 받은 arm64 `mongo:8.2.7`)가 있으면
  다른 아키텍처로 pull 할 때 대체될 수 있으니, 필요하면 다시 pull 하세요.
- 디스크: 이미지가 Docker VM 안에 한 번, Mac 의 `<out>/.work` 에 스테이징 파일로 한 번 더, 최종 분할 파일로 또 저장됩니다
  (Mac 에서 이미지 크기의 약 2.5배 + Docker VM 안의 이미지. 필요하면 Docker Desktop 디스크 한도를 늘리세요).
- x86_64 번들과 aarch64 번들 모두 어떤 Mac 에서든 만들 수 있습니다. GPU 와 일부 서드파티 선택 서비스는 x86_64 전용입니다(위 2단계 참고).
- 아카이브는 root 소유로, macOS 메타데이터(`._*` 파일 / 확장 속성) 없이 만들어져 Linux 에서 깨끗하게 풀립니다.

```bash
./make-offline-zip.sh                       # 대화식
./make-offline-zip.sh --yes --os ubuntu --arch x86_64 --services none --license-file ./license.txt
```

실제 실행 결과 발췌(100MB 분할로 만든 샘플 번들):

```
[info] Target: OS family=alpine, architecture=x86_64 (linux/amd64)
[info] Services in the bundle: mongo redis webapp sclab-proxy mail
[info] Removing unselected services from the bundled docker-compose.yml: qdrant ai-service node-vm-service sclab-agent gis-process mqtt-client mqtt-broker kafka-client
[info] Setting pull_policy: never in the bundled compose files
[info] Downloading Docker Engine 28.5.2 (x86_64)
[info] Downloading Docker Compose v2.40.3 (x86_64)
[ ok ] Docker Compose checksum verified
[info] [3/5] docker save mongo:8.2.7
[ ok ] License key stored in the bundle (license/LICENSE.key, mode 600)
[info] Creating the archive and splitting it into 100 MB parts (compressor: gzip)
[ ok ] 7 part(s) written
[ ok ] SHA256SUMS written
```

서버로 옮길 파일(출력 디렉터리의 모든 파일):

```
sclab-offline-20261120-x86_64.tar.gz.part001 ... .part00N   (기본 1GB 단위. --no-split 이면 sclab-offline-20261120-x86_64.tar.gz 하나)
SHA256SUMS            아카이브 파일, MANIFEST.json, install-offline.sh 의 체크섬
MANIFEST.json         번들 이름, 대상 OS/아키텍처, Docker/Compose 버전, 선택한 서비스,
                      이미지별 태그/이미지 ID/repo digest/크기, 파일 목록
install-offline.sh    설치 스크립트 (아카이브 안에도 사본이 있습니다)
```

> 라이선스 키는 아카이브 안에 **평문**으로 들어 있습니다. 파일을 기밀로 취급하세요.

## 4. 2단계 - 파일을 서버로 옮기기

**모든** 파일을 서버의 한 디렉터리에 복사합니다(USB 디스크, 내부 파일 공유, 점프 호스트를 통한 `scp` 등).
`install-offline.sh` 가 다시 검증하므로 여기서의 확인은 선택이지만, 전송 오류를 빨리 찾는 방법입니다.

```bash
cd /path/to/bundle
sha256sum -c SHA256SUMS
```

```
sclab-offline-20261120-x86_64.tar.gz.part001: OK
...
MANIFEST.json: OK
install-offline.sh: OK
```

## 5. 3단계 - 서버에서 설치하기

```bash
cd /path/to/bundle
sudo bash ./install-offline.sh          # 대화식 (install.sh 질문: 도메인, 비밀번호 등)
# 또는 모든 질문에 기본값으로 답하는 무인 설치(비밀번호 자동 생성, 기본 도메인):
sudo bash ./install-offline.sh --yes
```

단계는 다음과 같습니다(각 단계에 `== n/7 ... ==` 제목이 출력됩니다).

| 단계 | 동작 |
|---|---|
| 1/7 | root, Linux, x86_64 또는 aarch64 CPU 가 번들과 일치, 디스크 여유, 분할 파일 누락 여부 |
| 2/7 | `sha256sum -c SHA256SUMS` - 손상/누락 시 아무것도 바꾸기 전에 중단 |
| 3/7 | 분할 파일을 합쳐 `/opt/sclab/bundle-<이름>` 에 압축 해제(스트리밍: 전체 크기 사본을 따로 만들지 않음) |
| 4/7 | 번들의 Docker Engine + Compose 설치(systemd 유닛, OpenRC 서비스, 없으면 백그라운드 `dockerd`). **Docker 와 Compose 가 이미 동작하면 건너뜀** |
| 5/7 | 모든 이미지 `docker load` (같은 ID 가 이미 있으면 건너뜀). 이후 디스크 절약을 위해 풀어 둔 `.tar` 는 삭제(`--keep-images` 로 유지) |
| 6/7 | 저장소 파일을 `/opt/sclab/docker-images` 에 복사하고 번들의 라이선스 키로 `install.sh --offline` 실행 |
| 7/7 | `./run.sh` (`docker compose up -d`) 와 `docker compose ps` |

옵션: `--dir DIR`(분할 파일 위치), `--dest DIR`(기본 `/opt/sclab`), `--skip-docker`(기존 Docker 필수), `--force-docker`,
`--no-start`, `--yes`, `--keep-images`, `--reload-images`, `--help`.

오프라인 모드의 `install.sh` 는 AWS CLI 설치, AWS 자격 증명, ECR 로그인을 건너뛰고, 번들에 들어 있는 서비스만 묻고(기본값 **Yes**),
라이선스를 번들에서 읽고, JWT 키 쌍과 자체 서명 TLS 인증서를 (인터넷이 필요한 `alpine` key-generator 컨테이너 대신)
서버의 `openssl` 로 생성합니다.

실제 무인 설치 실행 발췌:

```
== 4/7 Docker Engine + Compose ==
[info] Installing Docker 28.5.2 static binaries to /usr/local/bin
[ ok ] Docker installed: Docker version 28.5.2, build ecc6942
== 5/7 Loading container images ==
[info] [3/5] docker load: mongo:8.2.7 (906 MB)
[ ok ] All 5 images loaded
== 6/7 Installing SCLAB Studio ==
[info] The license key from the bundle will be applied automatically.
License key loaded from the bundle: /opt/sclab/bundle-sclab-offline-20261120-x86_64/license/LICENSE.key
Offline mode: skipping AWS CLI / AWS credentials / ECR login (images are loaded from the bundle).
 - settings.json: replaced 'LICENSE CODE HERE' with <license key>.
 - jwt/: generated JWT key pair.
== 7/7 Starting services ==
NAME                          IMAGE              ...   STATUS
mongo                         mongo:8.2.7              Up 3 seconds
redis                         redis:8.2.1              Up 3 seconds
mail                          bytemark/smtp            Up 3 seconds
docker-images-sclab-proxy-1   nginx:alpine3.18         Up 3 seconds
```

일반 `install.sh` 실행과 마찬가지로 마지막에 **관리자 이메일과 비밀번호**가 출력됩니다. 반드시 기록해 두세요.

### 데이터 저장 위치 지정 (별도 디스크)

`install-offline.sh` 는 용량이 큰 두 데이터를 다른 디스크에 둘 수 있습니다. 대화식 실행에서는 두 질문 모두 나오며(**Enter = 기본값**),
`--yes` 에서는 옵션/환경변수 또는 기본값을 사용합니다.

| 대상 | 프롬프트 기본값 | 옵션 / 환경변수 | 적용 방식 |
|---|---|---|---|
| Docker 데이터(이미지·컨테이너·볼륨) | `/var/lib/docker` | `--docker-data-root DIR` / `SCLAB_DOCKER_DATA_ROOT` | dockerd 시작 **전에** `/etc/docker/daemon.json` 에 `"data-root"` 를 병합(다른 설정 보존, 기존 파일은 `daemon.json.sclab-bak-<시각>` 로 백업)하므로 `docker load` 가 처음부터 그 경로에 씁니다. systemd·OpenRC·폴백 모두 `--data-root` 플래그 없이 dockerd 를 시작하므로 같은 파일을 읽으며, 마지막에 `docker info` 로 Docker Root Dir 을 검증합니다. |
| 앱 데이터(MongoDB, Redis, Qdrant, 업로드 파일, 로그) | `<dest>/docker-images/data` | `--data-dir DIR` / `SCLAB_DATA_DIR` | `<dest>/docker-images/data` 가 `DIR` 로의 **심볼릭 링크**가 됩니다. 모든 스크립트와 compose 파일이 그대로 `./data/...` 를 쓰므로 run.sh, update.sh, logs.sh, optional-services 파일이 수정 없이 동작하고 업데이트 후에도 유지됩니다. |

주의:

- **마운트된** 디스크의 절대경로를 쓰세요. 먼저 마운트(+ `/etc/fstab` 등록)하지 않으면 데이터가 루트 디스크에 쌓입니다.
  스크립트는 파일시스템·마운트 위치·여유 용량을 보여주고, 경로가 `/` 위이거나 NFS/CIFS/FUSE 이거나 (Docker 의 경우) `noexec`/`nosuid`/`nodev` 마운트이면 경고하며,
  Docker 디스크가 이미지 크기(MANIFEST `images_bytes` x 1.2)보다 작으면 중단합니다.
- SELinux(enforcing): 디렉터리에 레이블을 지정하세요. 예: Docker `semanage fcontext -a -e /var/lib/docker /data/docker && restorecon -R /data/docker`,
  앱 데이터 `semanage fcontext -a -t container_file_t '/data/sclab(/.*)?' && restorecon -R /data/sclab` (해당 명령을 스크립트가 출력).
- 권한: root 가 쓸 수 있어야 하며 하위 디렉터리는 컨테이너가 직접 만들고 `chown` 합니다. root-squash 가 켜진 NFS 는 쓰지 마세요.
- Docker 가 **이미 설치된** 경우: 현재 데이터 경로를 보여주고 건드리지 않습니다. 다른 경로를 요청하면 기존 이미지·컨테이너·볼륨이 보이지 않게 되는 위험을 설명하고
  확인을 받으며(무인 실행은 기존 경로 유지), `--migrate-docker-data` 를 주면 Docker 를 멈추고 기존 디렉터리를 새 경로로 복사(rsync 또는 `cp -a`)합니다. 원본은 삭제하지 않습니다.
- 내용이 있는 기존 `<dest>/docker-images/data` 나 다른 곳을 가리키는 기존 링크는 자동으로 바꾸거나 옮기지 않습니다.
- 같은 값으로 다시 실행해도 변경 없음(멱등)입니다.
- `jq`/`python3` 가 없으면 `sed`/`awk` 로 병합합니다(일반적인 `daemon.json` 에는 충분하며, 시작 시 Docker 가 최종 검증).

```bash
sudo bash ./install-offline.sh --yes --docker-data-root /data/docker --data-dir /data/sclab
```

## 6. 설치 확인

```bash
cd /opt/sclab/docker-images
sudo docker compose ps          # 모든 서비스가 "Up"
sudo ./logs.sh                  # 로그 보기
```

`https://<도메인>` (기본 자리표시자는 `https://sclab-onprem` 이며 `/etc/hosts` 에서 127.0.0.1 로 연결됨)에 접속해 설치 마지막에 출력된
관리자 계정으로 로그인합니다. 자체 서명 인증서라 브라우저 경고가 나오며, `cert/cert.pem` / `cert/privkey.pem` 을 자체 인증서로 교체하면 사라집니다.

레지스트리가 필요 없는지 확인: `grep -c "pull_policy: never" docker-compose.yml` 값이 서비스 수와 같고,
`/opt/sclab/docker-images/.offline` 파일이 있어야 합니다(이 표시 파일이 `run.sh`, `pull.sh`, `update.sh` 의 ECR 로그인을 끕니다).

## 7. 업데이트 / 재설치

- `install-offline.sh` 를 **다시 실행**해도 안전합니다. 검증된 체크섬, 압축 해제, Docker, 적재된 이미지, 기존 설정(`.init`)을 감지해 건너뛰고 서비스만 (재)기동합니다.
- **일부 이미지만 업데이트**(예: 새 릴리스의 `webapp`): `make-offline-update-zip.sh` 로 작은 업데이트 번들을 만들어 `update-offline-images.sh` 로 적용합니다 - 8절 참고(롤링 업데이트, 롤백, 이력).
- **전체 업데이트**: `make-offline-zip.sh` 로 새 번들을 만들어 옮긴 뒤 `install-offline.sh` 를 다시 실행합니다(번들 이름이 다르면 새 디렉터리에 풀리고 바뀐 이미지가 적재됩니다).
  기존 `.init` 이 있으면 예전 저장소 파일을 그대로 두므로, 새 compose/env 변경은 `/opt/sclab/bundle-<이름>/repo` 에서 직접 반영한 뒤 `./run.sh` 하세요.
  오프라인에서는 `update.sh` / `docker compose pull` 이 비활성화됩니다.
- **재설정**: `/opt/sclab/docker-images/.init` 을 지우고 번들의 `repo/` 파일로 복원한 뒤 `install-offline.sh` 를 다시 실행합니다.
- 나중에 선택 서비스를 켜고 끄기: `sudo ./service-manage.sh` (이미지가 적재된 서비스만 기동됩니다).

## 8. 일부 이미지만 업데이트 (오프라인 업데이트)

이미 설치된 서버에서 몇 개의 이미지만 바뀌었을 때 - 대개 새 SCLAB 릴리스의 **`webapp`** - 사용합니다.
전체 번들(Docker, 모든 이미지, 수 GB)을 다시 만들어 옮기는 대신, 고른 이미지만 담은 작은 **업데이트 번들**을 만듭니다.
서버의 설정(`.env` 파일, `settings.json`, 인증서, `data/`)은 건드리지 않습니다. 업데이트 번들에는 라이선스 키도, Docker Engine 도 들어 있지 않습니다.

```
 인터넷이 되는 PC / 서버                                폐쇄망 서버
 ───────────────────────────                            ───────────────────────────
 ./make-offline-update-zip.sh  ──►  <이름>.tar.gz[.part*]  ──►  sudo bash ./update-offline-images.sh
   (서비스 선택, pull,               <이름>.SHA256SUMS          (검증, 압축 해제, docker load, 변경점 표시,
    docker save, 분할)               <이름>.MANIFEST.json        적용, 헬스 확인, 이력, 롤백)
                                     update-offline-images.sh
```

### 8.1 업데이트 번들 만들기 (인터넷이 되는 머신, Linux 또는 macOS)

전체 번들과 마찬가지로 이 저장소를 받은 곳에서 실행합니다(3절 및 "Mac 에서 번들 만들기" 참고).

```bash
./make-offline-update-zip.sh                      # 대화식: ↑/↓(또는 j/k) 이동, Space 체크, Enter 확정
# 또는 무인 실행:
./make-offline-update-zip.sh --yes --services webapp,ai-service --out ./sclab-update-out
```

메뉴에는 필수 5개를 포함한 모든 서비스가 나오며 `webapp` 이 기본 체크되어 있습니다. 터미널이 없으면 번호 입력 방식으로 바뀝니다.
AWS CLI 가 없으면 설치하고, ECR 에 로그인한 뒤, 선택한 이미지만 `docker pull --platform linux/amd64`(`--arch aarch64` 이면 `linux/arm64`) + `docker save` 하여
압축한 아카이브를 만듭니다(기본 1GB 단위 분할, 또는 하나의 파일. 아래 참고).

| 옵션 | 의미 |
|---|---|
| `--services 목록` | 쉼표로 구분한 서비스. 예: `webapp,mail` (`--list-services` 로 전체 확인) |
| `--arch ARCH` | 대상 CPU 아키텍처: `x86_64`(= `amd64`, 기본값) 또는 `aarch64`(= `arm64`). 대화식 실행에서는 메뉴로 묻습니다. GPU 와 일부 선택 서비스는 x86_64 전용 |
| `--out 디렉터리` | 출력 디렉터리(기본 `./sclab-update-out`) |
| `--name 이름` | 번들 이름(기본 `sclab-update-<YYYYMMDD-HHMMSS>-<arch>`) |
| `--part-size 크기` | 분할 파일 크기: `500M`, `5G`, 단위 없는 숫자는 MB (기본 `1G`) |
| `--no-split` | 분할하지 않고 하나의 `<이름>.tar.gz` 로 만들기 |
| `--with-compose` | 이 저장소의 compose / 스크립트 / 설정 파일도 함께 담기(8.3 참고). 기본은 이미지만 |
| `--base-bundle 이름` / `--base-manifest 파일` | 이 업데이트가 어느 전체 번들용인지 기록(서버에서 표시/확인) |
| `--no-pull` | 로컬에 이미 있는 이미지를 사용(AWS CLI, ECR 로그인 생략) |

**분할 방식.** 전체 번들과 같습니다. 기본값은 1GB 단위 분할이며, 대화식으로 실행하면 *분할 안 함* / *GB 단위* / *MB 단위* 를 묻습니다(Enter = 1GB).
대화식이 아니면 `--no-split`(하나의 `<이름>.tar.gz`), `--part-size 5G`, `--part-size 500M` 을 사용합니다. 분할 크기가 번들보다 크면 하나의 파일이 만들어집니다.
`update-offline-images.sh` 는 하나의 파일도, 분할 파일도 모두 처리합니다.

출력 파일은 모두 번들 이름으로 시작하므로, **같은** 출력 디렉터리에 업데이트 번들을 여러 번 만들어도 파일이 섞이지 않습니다.

```
sclab-update-20261120-153045-x86_64.tar.gz.part001   (... .part002 ...; --no-split 이면 sclab-update-20261120-153045-x86_64.tar.gz)
sclab-update-20261120-153045-x86_64.SHA256SUMS
sclab-update-20261120-153045-x86_64.MANIFEST.json     (종류, 생성 시각, 이미지별 태그 / 이미지 ID / repo digest / 크기, 서비스, 아키텍처)
update-offline-images.sh                              (모든 번들에 공통인 같은 스크립트)
```

### 8.2 파일을 서버로 옮기기

번들의 **모든** 파일(`<이름>.*` 과 `update-offline-images.sh`)을 서버의 **한 디렉터리**에 복사합니다(USB, `scp` 등).
여러 업데이트 번들의 파일이 같은 디렉터리에 있어도 되며, 번들은 이름 접두사로 구분됩니다.

### 8.3 서버에서 업데이트 적용하기

```bash
cd /복사한/파일이/있는/디렉터리
sudo bash ./update-offline-images.sh                # 메뉴 / 확인 질문
sudo bash ./update-offline-images.sh --yes --bundle sclab-update-20261120-153045-x86_64    # 무인 실행
```

- 현재 디렉터리(또는 `--dir`)를 살펴 업데이트 번들을 이름, 날짜, 서비스, 크기, 상태(`new` / `applied <날짜>`)와 함께 보여 줍니다.
  번들이 **하나**면 확인만 묻고, **여러 개**면 화살표 메뉴가 나옵니다(↑/↓ 이동, **Enter** 는 강조된 하나 적용, **Space** 로 여러 개를 체크한 뒤
  Enter 하면 **날짜순**으로 차례로 적용). `--all` 은 아직 적용하지 않은 번들을 오래된 것부터 모두 적용하고, `--bundle 이름[,이름]` 은 메뉴 없이 지정합니다.
- 설치 위치는 자동으로 찾습니다(현재 디렉터리에 `docker-compose.yml` 이 있으면 그곳, 아니면 `/opt/sclab/docker-images`). 다르면 `--install-dir 디렉터리`.
- 순서: 체크섬 검증(손상/누락된 파일이 있으면 중단) → 아키텍처 확인 → 분할 파일을 합쳐 임시 디렉터리(번들 옆, 또는 `--work-dir`)에 해제 → `docker load` →
  새 이미지 ID 와 실행 중인 컨테이너의 이미지를 비교해 **바뀐 서비스만** 표시 → 확인 → 적용 → 헬스 확인.
- **적용 방식:** `webapp` 은 롤링으로 교체합니다(새 컨테이너를 기존 것 옆에 띄우고 30초 동안 동작을 확인한 뒤 이전 컨테이너를 종료, 이어서 `sclab-proxy` 재시작).
  그 밖의 서비스는 `docker compose up -d --no-deps <서비스>` 로 재생성합니다. 이미지 pull 이나 레지스트리 접속은 하지 않습니다(오프라인 모드 / `pull_policy: never`).
- 컨테이너가 실행 중이고(헬스체크가 있으면 `healthy`) 몇 초 동안 유지되면 정상으로 봅니다. 새 webapp 컨테이너가 정상이 되지 않으면 기존 컨테이너는 그대로 두고 새 컨테이너만 제거합니다.
- 변경 **전에** 지금까지 쓰던 이미지를 `<저장소>:rollback-<시각>` 태그로 보존하고, `<설치 디렉터리>/.offline-updates/<번들>/` 에 롤백 정보를 기록합니다.
  이 태그는 자동으로 지우지 않으니, 필요 없어지면 `docker image rm <태그>` 로 직접 정리하세요.
- **설정 파일(`--with-compose` 로 만든 번들):** 새 compose / 스크립트 파일을 설치된 파일과 비교해 반영합니다. 직접 바꾸지 않은 파일은 교체하고,
  바꾼 파일은 3-way 병합(내 값 유지, 충돌 시 내 파일은 그대로 두고 새 버전을 `<파일>.upstream` 으로 옆에 저장)하며, 새 파일은 추가합니다.
  `*.env`, `settings.json`, `cert/`, `jwt/`, `data/`, `.init`, `.offline` 은 **절대** 덮어쓰지 않습니다. 변경 내용(diff)을 보여 주고 확인을 받으며(`--no-config` 로 이 부분 생략),
  교체되는 파일은 `.offline-updates/<번들>/config-backup/` 에 백업됩니다.
- `--dry-run` 은 체크섬 검증과 변경 예정 표시까지만 하고, `--list` 는 번들 목록만 보여 줍니다.

예시(디렉터리에 번들 2개, 메뉴에서 두 번째 선택):

```
$ sudo bash ./update-offline-images.sh
[ ok ] Found 2 update bundle(s) in /srv/updates:
  sclab-update-20261118-101500-x86_64
      2026-11-18T01:15:03 | webapp | 1.2 GB | applied 2026-11-18
  sclab-update-20261120-153045-x86_64
      2026-11-20T06:30:58 | webapp,mail | 1.5 GB | new
...
== Changes in sclab-update-20261120-153045-x86_64 ==
  SERVICE   IMAGE                    RUNNING       NEW           ACTION
  webapp    onpremise-webapp:latest   510fb0d29314  b329f6a69817  UPDATE (rolling, no downtime)
  mail      postfix:5.2.1             4e07dabae3fb  4e07dabae3fb  unchanged
Apply sclab-update-20261120-153045-x86_64 now? (1 service(s) will be restarted) [Y/n]:
```

### 8.4 롤백

```bash
sudo bash ./update-offline-images.sh --rollback            # 가장 최근에 적용한 번들
sudo bash ./update-offline-images.sh --rollback <번들-이름>
```

이전 이미지를 원래 태그로 되돌리고, 그 이미지로 서비스를 다시 만들며, 업데이트가 바꾼 설정 파일도 복원합니다.
업데이트 중 헬스 확인에 실패하면 바로 롤백할지 묻습니다(`--yes` 에서는 자동으로 롤백하며, `--no-auto-rollback` 으로 끌 수 있습니다).

### 8.5 적용 이력과 중복 적용 감지

실행 결과는 `<설치 디렉터리>/.offline-updates/history.tsv`(시각, 번들, `applied` / `failed` / `rolled-back`)에 남습니다.
이미 적용한 번들을 다시 고르면 언제 적용했는지 알려 주고 다시 적용할지 묻습니다(`--yes` 는 건너뛰고, `--force` 는 다시 적용). 롤백한 번들은 다시 적용할 수 있습니다.

### 8.6 문제 해결 (업데이트)

| 메시지 / 증상 | 원인 / 해결 |
|---|---|
| `No update bundle found in ...` | 파일이 있는 디렉터리에서 실행하거나 `--dir` 사용. `<이름>.MANIFEST.json` 이 있어야 함 |
| `Missing bundle file(s): ...` | 분할 파일 일부를 복사하지 않음. 모든 `<이름>.tar.gz.partNNN` 을 `<이름>.SHA256SUMS` 옆에 복사 |
| `Checksum verification FAILED` | 전송 중 파일 손상. 해당 파일을 다시 복사. 아무것도 변경되지 않았음 |
| `Architecture mismatch` | 번들과 서버의 CPU 아키텍처가 다름. 서버에 맞게 `--arch x86_64` 또는 `--arch aarch64` 로 다시 만들기 |
| `Several update bundles found and no terminal` | 무인 실행에서는 `--bundle 이름` 또는 `--all` 사용 |
| `Could not find the installed docker-images directory` | 설치 디렉터리에서 실행하거나 `--install-dir /opt/sclab/docker-images` 지정 |
| `Not enough free disk space ...` | 공간 확보 또는 더 큰 디스크에 `--work-dir`(이미지는 Docker 데이터 디렉터리에도 적재됨) |
| `... failed its health check` | 기존 webapp 은 계속 동작. 표시된 로그로 원인을 확인하거나 롤백(8.4) |
| `CONFLICT <파일>` (설정 병합) | 나와 번들이 같은 줄을 바꿈. `<파일>.upstream` 내용을 `<파일>` 에 직접 병합한 뒤 `.upstream` 삭제 |

## 9. 문제 해결

| 메시지 / 증상 | 원인 / 해결 |
|---|---|
| `Missing bundle file(s): ...` | 분할 파일 일부를 복사하지 않음. 모든 `*.partNNN` 을 `SHA256SUMS` 옆에 복사 |
| `Checksum verification FAILED` | 전송 중 파일 손상. 해당 파일을 다시 복사. 아무것도 설치되지 않았음 |
| `Architecture mismatch` | 번들과 서버의 CPU 아키텍처가 다름. 서버에 맞게 `--arch x86_64` 또는 `--arch aarch64` 로 다시 만들기 |
| `Not enough disk space ...` | 공간 확보 또는 더 큰 디스크에 `--dest`. Docker 이미지는 `/var/lib/docker` 에도 공간이 필요 |
| `Docker was installed but the daemon did not start` | `journalctl -u docker`(systemd) 또는 `/var/log/dockerd.log` 확인, `iptables`/`nft` 와 커널 `overlay` 지원 확인 |
| 컨테이너에 네트워크가 없음 | OS 설치 매체에서 `iptables`(또는 nftables) 설치. firewalld 를 쓰는 RHEL 계열은 firewalld 기동 후 `systemctl restart docker` |
| `openssl` / `sed` / `awk` 없음 | 오프라인에서는 받을 수 없으니 OS 설치 매체에서 설치 |
| install.sh 가 라이선스를 물음 | 번들을 `--no-license`(또는 빈 키)로 만들었음. 직접 입력 |
| `ai-service` 의 Qdrant 문제 | `qdrant` 없이 `ai-service` 만 선택함. 둘 다 선택해 번들 다시 생성 |
| `vllm` 이 시작되지 않음 | vllm compose 가 시작할 때 `apt-get`/`pip` 를 실행(인터넷 필요)하고 모델도 번들에 없음 |
| ollama / speaches 에 모델이 없음 | 모델은 번들에 없음. 서버로 따로 복사 |
