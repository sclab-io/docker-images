# 폐쇄망(오프라인) 설치 가이드

> English version: [offline-install.md](offline-install.md) · [README](../README-ko.md) 로 돌아가기

이 문서는 **인터넷이 전혀 없는** 서버(Docker 저장소, GitHub, AWS/ECR 모두 접속 불가)에 SCLAB Studio 를 설치하는 방법입니다.
서버에 필요한 모든 것 - Docker Engine, Docker Compose, 모든 컨테이너 이미지, 이 저장소의 파일, 라이선스 키 - 을
**인터넷이 되는** 머신에서 분할 파일 몇 개로 묶어 두고, 그 파일을 서버로 옮겨 스크립트 하나만 실행합니다.

```
 인터넷이 되는 PC / 서버                           폐쇄망 서버
 ───────────────────────────                       ───────────────────────────
 ./make-offline-zip.sh   ──►  *.part001 ...   ──►   sudo bash ./install-offline.sh
   (이미지 pull, Docker,       SHA256SUMS            (검증, 압축 해제, Docker 설치,
    라이선스, 1GB 분할)        MANIFEST.json          docker load, install.sh, 기동)
                               install-offline.sh
```

## 1. 개요

| 스크립트 | 실행 위치 | 하는 일 |
|---|---|---|
| `make-offline-zip.sh` | 인터넷이 되는 머신(모든 Linux) | 대상 OS/아키텍처와 서비스를 고르게 하고, AWS CLI 가 없으면 설치하고, ECR 에 로그인하고, Docker Engine + Compose 를 내려받고, 선택한 모든 이미지를 `docker pull` + `docker save` 한 뒤, 라이선스 키와 함께 하나의 압축 파일로 묶어 1GB 단위로 분할하고 `SHA256SUMS`, `MANIFEST.json` 을 만듭니다 |
| `install-offline.sh` | 폐쇄망 서버(root) | 체크섬을 검증하고, 분할 파일을 합쳐 압축을 풀고, 번들의 Docker + Compose 를 설치하고(이미 Docker 가 있으면 건너뜀), 이미지를 `docker load` 하고, `install.sh --offline` 을 실행(라이선스는 번들에서 자동 적용)한 뒤 서비스를 기동합니다 |

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

- 번들과 **같은 CPU 아키텍처**의 Linux, `bash`, `tar`, `gzip`, `sha256sum`, `openssl`, `awk`, `sed`, `grep`, `iptables` 또는 `nftables`
- 여유 디스크: 번들 크기(압축 해제) **+** 이미지 크기(Docker 데이터 디렉터리, 보통 `/var/lib/docker`)

## 3. 1단계 - 번들 만들기 (인터넷이 되는 머신)

```bash
git clone https://github.com/sclab-io/docker-images.git
cd docker-images
./make-offline-zip.sh
```

대화식으로 진행됩니다.

1. **대상 OS 계열** (화살표 메뉴: ↑/↓ 또는 `j`/`k` 이동, Enter 선택). CPU 아키텍처는 x86_64(amd64) 로 고정이며
   **aarch64/arm64 는 아직 지원되지 않습니다** (`--arch aarch64` 는 오류로 중단).
2. **서비스 선택** - 체크박스 메뉴. ↑/↓(또는 `j`/`k`)로 이동, **Space** 로 토글, `a` = 전체, `n` = 없음, **Enter** = 계속.
   필수 서비스는 잠금 표시되며 해제할 수 없습니다. 터미널이 아닐 때(파이프/CI)나 `TERM=dumb` 에서는 번호 입력 방식으로 자동 전환됩니다.
   `mongo redis webapp sclab-proxy mail` 은 항상 포함됩니다. 선택 항목: `qdrant ai-service node-vm-service sclab-agent gis-process
   mqtt-client mqtt-broker kafka-client tileserver gotenberg vision vision-gpu ollama vllm speaches`.
   선택하지 않은 서비스는 이미지를 받지 않고 번들의 `docker-compose.yml` 에서도 빠집니다.
3. **라이선스 키**(입력 숨김) - 번들 안 `license/LICENSE.key`(권한 600)로 저장되고 서버에서 자동 적용됩니다.
4. 필요하면 AWS CLI 설치 / `aws configure` / ECR 로그인, 이어서 pull, save, 압축, 분할.

비대화식 예:

```bash
./make-offline-zip.sh --yes --os ubuntu --arch x86_64 \
  --services qdrant,ai-service,node-vm-service,gotenberg \
  --license-file ./my-license.txt --out ./sclab-offline-out
```

전체 옵션은 `./make-offline-zip.sh --help` (`--list-services` 로 서비스 목록 확인, `--part-size MB`, `--no-license`,
`--docker-version`, `--compose-version`, `--work-dir`, 로컬에 이미 있는 이미지를 쓰는 `--no-pull`).

### Mac(Intel / Apple Silicon)에서 번들 만들기

`make-offline-zip.sh` 는 macOS 에서도 실행됩니다(번들은 항상 **Linux** 서버용이며 `install-offline.sh` 는 Linux 전용입니다).

- 준비물: 실행 중인 Docker 엔진(**Docker Desktop**, **OrbStack**, **Colima**), Homebrew(선택, AWS CLI 설치에 사용), macOS 기본 도구
  (기본 bash 3.2 와 BSD 도구로 동작). AWS CLI 가 없으면 자동 설치합니다: `brew install awscli`, 없으면 공식 설치 프로그램을 현재 사용자 전용(`~/.local/aws-cli`, sudo 불필요)으로 설치합니다.
- **대상**은 메뉴 / `--os` / `--arch` 로 고른 서버이며 Mac 의 CPU 가 아닙니다. Apple Silicon 에서도 메뉴 기본값은 x86_64 입니다.
  이미지는 `docker pull --platform linux/amd64`(또는 `linux/arm64`)로 받아 `docker save --platform ...` 로 저장하며, 다른 아키텍처 코드는 실행하지 않습니다(에뮬레이션 없음).
  서버용 Docker Engine tgz 와 Compose 바이너리는 번들에 **내려받기만** 하고 Mac 에는 설치하지 않습니다.
- 이미지는 로컬 Docker 엔진에 pull 되어 같은 이름의 로컬 태그를 바꿉니다. 엔진에 같은 태그의 다른 아키텍처 이미지(예: 직접 받은 arm64 `mongo:8.2.7`)가 있으면
  다른 아키텍처로 pull 할 때 대체될 수 있으니, 필요하면 다시 pull 하세요.
- 디스크: 이미지가 Docker VM 안에 한 번, Mac 의 `<out>/.work` 에 스테이징 파일로 한 번 더, 최종 분할 파일로 또 저장됩니다
  (Mac 에서 이미지 크기의 약 2.5배 + Docker VM 안의 이미지. 필요하면 Docker Desktop 디스크 한도를 늘리세요).
- 현재 SCLAB 이미지는 x86_64 로 만드세요: `onpremise-webapp` 이 아직 amd64 전용이라 `--arch aarch64` 는 오류로 중단됩니다(현재 미지원). 메일 릴레이는 멀티아키(`boky/postfix`, 아래 참고)로 바뀌었습니다. 멀티아키 `onpremise-webapp` 이 ECR 에 올라오기 전에는 aarch64 번들을 만들 수 없습니다.
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
sclab-offline-20261120-x86_64.tar.gz.part001 ... .part00N   (기본 1GB 단위)
SHA256SUMS            분할 파일, MANIFEST.json, install-offline.sh 의 체크섬
MANIFEST.json         번들 이름, 대상 OS/아키텍처, Docker/Compose 버전, 선택한 서비스,
                      이미지별 태그/이미지 ID/repo digest/크기, 분할 파일 목록
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
| 1/7 | root, Linux, 번들과 CPU 아키텍처 일치, 디스크 여유, 분할 파일 누락 여부 |
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
- **업데이트**: `make-offline-zip.sh` 로 새 번들을 만들어 옮긴 뒤 `install-offline.sh` 를 다시 실행합니다(번들 이름이 다르면 새 디렉터리에 풀리고 바뀐 이미지가 적재됩니다).
  기존 `.init` 이 있으면 예전 저장소 파일을 그대로 두므로, 새 compose/env 변경은 `/opt/sclab/bundle-<이름>/repo` 에서 직접 반영한 뒤 `./run.sh` 하세요.
  오프라인에서는 `update.sh` / `docker compose pull` 이 비활성화됩니다. *(기존 설치의 제자리 업그레이드 자동화는 아직 없습니다.)*
- **재설정**: `/opt/sclab/docker-images/.init` 을 지우고 번들의 `repo/` 파일로 복원한 뒤 `install-offline.sh` 를 다시 실행합니다.
- 나중에 선택 서비스를 켜고 끄기: `sudo ./service-manage.sh` (이미지가 적재된 서비스만 기동됩니다).

## 8. 문제 해결

| 메시지 / 증상 | 원인 / 해결 |
|---|---|
| `Missing bundle file(s): ...` | 분할 파일 일부를 복사하지 않음. 모든 `*.partNNN` 을 `SHA256SUMS` 옆에 복사 |
| `Checksum verification FAILED` | 전송 중 파일 손상. 해당 파일을 다시 복사. 아무것도 설치되지 않았음 |
| `Architecture mismatch` | 번들과 서버의 CPU 아키텍처가 다름. `--arch` 로 다시 만들기 |
| `Not enough disk space ...` | 공간 확보 또는 더 큰 디스크에 `--dest`. Docker 이미지는 `/var/lib/docker` 에도 공간이 필요 |
| `Docker was installed but the daemon did not start` | `journalctl -u docker`(systemd) 또는 `/var/log/dockerd.log` 확인, `iptables`/`nft` 와 커널 `overlay` 지원 확인 |
| 컨테이너에 네트워크가 없음 | OS 설치 매체에서 `iptables`(또는 nftables) 설치. firewalld 를 쓰는 RHEL 계열은 firewalld 기동 후 `systemctl restart docker` |
| `openssl` / `sed` / `awk` 없음 | 오프라인에서는 받을 수 없으니 OS 설치 매체에서 설치 |
| install.sh 가 라이선스를 물음 | 번들을 `--no-license`(또는 빈 키)로 만들었음. 직접 입력 |
| `ai-service` 의 Qdrant 문제 | `qdrant` 없이 `ai-service` 만 선택함. 둘 다 선택해 번들 다시 생성 |
| `vllm` 이 시작되지 않음 | vllm compose 가 시작할 때 `apt-get`/`pip` 를 실행(인터넷 필요)하고 모델도 번들에 없음 |
| ollama / speaches 에 모델이 없음 | 모델은 번들에 없음. 서버로 따로 복사 |
