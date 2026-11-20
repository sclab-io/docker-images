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

인터넷이 되는 머신(Linux, x86_64 또는 aarch64):

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

1. **대상 OS 계열**과 **CPU 아키텍처** (메뉴).
2. **서비스 선택** - 체크박스 메뉴. 번호를 입력하면 토글, `a` = 전체, `n` = 없음, Enter = 계속.
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

## 9. 검증한 것과 하지 못한 것

모든 시험은 Docker(Docker Desktop, x86_64 호스트)에서 했고, 서버는 **네트워크가 없는**(`--network none`) 특권 컨테이너로 모의했습니다.
따라서 어느 설치도 인터넷에 접속하지 않았습니다.

| 항목 | 방법 | 결과 |
|---|---|---|
| 실제 ECR 이미지 + AWS CLI 자동 설치 | curl/unzip/aws 가 없는 `ubuntu:24.04` 컨테이너에서 실제 AWS 자격 증명으로 `make-offline-zip.sh` | 없는 도구와 AWS CLI 가 자동 설치되고, ECR 로그인과 실제 `onpremise-webapp` pull 이 성공했으며 실제 1GiB 분할 파일이 만들어짐 |
| aarch64 의 AWS CLI | `linux/arm64` 컨테이너(QEMU)에서 동일 실행 | AWS CLI, Docker, Compose 의 aarch64 다운로드와 ECR 로그인 성공 |
| 9개 배포판 오프라인 설치 | 실제 이미지로 만든 번들로 `install-offline.sh --yes` | Ubuntu 22.04/24.04, Debian 12, Rocky 9, Alma 8/9, Fedora, Amazon Linux 2023, openSUSE Leap 15.6, Alpine 3.20 모두 설치되어 mongo, redis, mail, webapp, sclab-proxy 기동 |
| systemd 서비스 | systemd 컨테이너(Ubuntu 24.04, Debian 12), `docker restart` 로 재부팅 모사 | 유닛 등록·enable, 재시작 후 Docker 와 모든 컨테이너가 자동 기동, 재실행 시 끝난 단계 건너뜀 |
| OpenRC | OpenRC 가 있는 Alpine | 서비스 등록, OpenRC 로 Docker 기동, 설치 완료 |
| 오류 경로 | 손상/누락 분할 파일, 아키텍처 불일치, root 아님 | 모두 설치 전에 명확한 메시지와 함께 중단 |
| shellcheck | 경고 수준 | 깨끗함 |

시험 중 찾아 고친 것: `curl`/`unzip` 이 없는 머신에서 `make-offline-zip.sh` 가 중단되던 문제(이제 없는 도구를 설치), OpenRC 서비스가 `dockerd` 와 pid 파일을 공유해 기동에 실패하던 문제,
init 시스템 실패 시 메시지 없이 끝나던 문제, 대상 아키텍처용 이미지가 없어도 번들이 만들어지던 문제(이제 오류).

**한계 / 미검증**

- **현재 필수 이미지로는 aarch64 번들을 만들 수 없습니다**: `onpremise-webapp` 과 `bytemark/smtp` 가 amd64 전용이라 `make-offline-zip.sh --arch aarch64` 는 오류로 중단됩니다.
  aarch64 도구(AWS CLI, Docker, Compose 다운로드)만 확인했습니다.
- **라이선스와 외부 접속**: 시험에는 가짜 라이선스 키를 썼습니다. 이 키로는 `webapp` 컨테이너가 (인터넷이 되는 환경에서도) 재시작을 반복하며, 격리 실행 중 `app.sclab.io` 를 반복 조회했습니다.
  라이선스 확인일 가능성이 높고, 그렇다면 **실제 라이선스가 폐쇄망 서버에는 없는 그 호스트 접속을 요구할 수 있습니다**. 유효한 키가 없어 확인하지 못했으니 실제 라이선스로 검증해 주세요.
- 미검증: SELinux enforcing 호스트(시험 컨테이너는 Docker Desktop VM 커널을 공유), 실제 하드웨어/실제 부팅(재부팅이 아니라 컨테이너 재시작), RHEL 자체(Rocky/Alma 사용),
  위 버전 외의 SUSE/Amazon Linux, Vision / Ollama / vLLM / Speaches / 타일 서버 / Gotenberg 부가 구성, CPU 부하가 큰 상황의 `dockerd` 기동
  (openSUSE 병렬 실행 한 번에서 containerd 시작 시간 초과가 났고 재실행은 통과).
- 최소 컨테이너 이미지에는 실제 서버에 있는 도구(`iptables`, `openssl`, Amazon Linux 최소판의 `groupadd` 등)가 빠져 있습니다. 시험 이미지에는 일반 서버 설치처럼
  `openssl`, `iptables`, `procps`, `hostname` 을 추가했습니다.
