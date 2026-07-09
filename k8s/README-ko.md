# Kubernetes 설정

> English version: [README.md](README.md)

이 폴더는 SCLAB 계열 서비스를 Kubernetes에 올릴 때 필요한 준비 작업과 샘플 매니페스트를 정리한 곳입니다.

## Secret 만들기

```bash
kubectl create secret docker-registry sclab-ecr-sec \
  --docker-server=873379329511.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2)
```

## MQTT broker용 JWT 키 생성

```bash
mkdir jwt
ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwtRS256.key
openssl rsa -in ./jwt/jwtRS256.key -pubout -outform PEM -out ./jwt/jwtRS256.key.pub
```

## SSL 키 생성

```bash
mkdir cert
openssl genrsa -out ./cert/privkey.pem 2048
openssl req -new -sha256 -key ./cert/privkey.pem -out ./cert/csr.pem
openssl x509 -req -in ./cert/csr.pem -signkey ./cert/privkey.pem -out ./cert/cert.pem
```

## SCLAB API용 JWT 키 생성

```bash
ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwt-api-RS256.key
openssl rsa -in ./jwt/jwt-api-RS256.key -pubout -outform PEM -out ./jwt/jwt-api-RS256.key.pub
```

## ConfigMap 적용

```bash
kubectl apply -f config-common.yaml
kubectl apply -f config-webapp.yaml
kubectl apply -f config-ai-service.yaml
```

## PVC / StatefulSet / Deployment / Ingress

각 단계의 예시는 `README.md`를 참고하세요. 이 파일은 핵심 명령만 한국어로 정리했습니다.

## 참고

- Secret, ConfigMap, PVC, StatefulSet, Deployment, Ingress 순서로 배포를 준비합니다.
- `kubectl cp`는 인증서와 JWT 키를 Pod 안으로 복사할 때 사용합니다.
- 로드밸런서나 Ingress는 환경에 맞게 별도로 준비해야 합니다.
