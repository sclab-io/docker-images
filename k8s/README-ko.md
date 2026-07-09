# Kubernetes 설정

> English version: [README.md](README.md)

이 문서는 SCLAB 계열 서비스를 Kubernetes에 배포할 때 필요한 준비 작업과 샘플 매니페스트를 정리한 것입니다.

## Secret 만들기

```bash
kubectl create secret docker-registry sclab-ecr-sec \
  --docker-server=873379329511.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2)
```

## MQTT broker용 JWT 키 파일 만들기

```bash
mkdir jwt
ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwtRS256.key
# 비밀번호는 비워 두고 Enter를 누르세요
openssl rsa -in ./jwt/jwtRS256.key -pubout -outform PEM -out ./jwt/jwtRS256.key.pub
```

## MQTT broker용 SSL 키 파일 만들기

* 자체 키가 있으면 그 키를 그대로 사용해도 됩니다.

```bash
mkdir cert
openssl genrsa -out ./cert/privkey.pem 2048
openssl req -new -sha256 -key ./cert/privkey.pem -out ./cert/csr.pem
openssl x509 -req -in ./cert/csr.pem -signkey ./cert/privkey.pem -out ./cert/cert.pem
```

## SCLAB API용 JWT 키 파일 만들기

```bash
ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwt-api-RS256.key
# 비밀번호는 비워 두고 Enter를 누르세요
openssl rsa -in ./jwt/jwt-api-RS256.key -pubout -outform PEM -out ./jwt/jwt-api-RS256.key.pub
```

## ConfigMap

ConfigMap을 적용합니다.

```bash
kubectl apply -f config-common.yaml
kubectl apply -f config-webapp.yaml
kubectl apply -f config-ai-service.yaml
```

## PVC

```bash
kubectl apply -f pvc.yaml
```

## StatefulSet

```bash
kubectl apply -f statefulset-mongodb.yaml
kubectl apply -f statefulset-qdrant.yaml
kubectl apply -f statefulset-redis.yaml
```

## cert와 jwt 폴더를 PVC에 복사

```bash
kubectl apply -f deployment-webapp.yaml
kubectl get pods -l app=sclab-webapp
kubectl cp ./cert <sclab-webapp-pod-name>:/data/cert
kubectl cp ./jwt <sclab-webapp-pod-name>:/data/jwt
kubectl rollout restart deployment/sclab-webapp
```

## Deployment

```bash
kubectl apply -f deployment-ai-service.yaml
kubectl apply -f deployment-gis-process.yaml
kubectl apply -f deployment-kafka-client.yaml
kubectl apply -f deployment-mqtt-broker.yaml
kubectl apply -f deployment-mqtt-client.yaml
```

## Ingress

nginx ingress가 필요하면 아래를 적용합니다.

```bash
kubectl apply -f ingress.yaml
```
