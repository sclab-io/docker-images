Kubernetes setup
=================

## create secret
kubectl create secret docker-registry sclab-ecr-sec \
  --docker-server=873379329511.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2)

## create JWT key file for mqtt-broker
~~~bash
$ mkdir jwt
$ ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwtRS256.key
# empty passphrase - just press enter
$ openssl rsa -in ./jwt/jwtRS256.key -pubout -outform PEM -out ./jwt/jwtRS256.key.pub
~~~

## create SSL key file for mqtt-broker
* If you have your own key file just use that key
~~~bash
$ mkdir cert
$ openssl genrsa -out ./cert/privkey.pem 2048
$ openssl req -new -sha256 -key ./cert/privkey.pem -out ./cert/csr.pem
$ openssl x509 -req -in ./cert/csr.pem -signkey ./cert/privkey.pem -out ./cert/cert.pem
~~~

## create JWT key file for SCLAB API
~~~bash
$ ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwt-api-RS256.key
# empty passphrase - just press enter
$ openssl rsa -in ./jwt/jwt-api-RS256.key -pubout -outform PEM -out ./jwt/jwt-api-RS256.key.pub
~~~

## ConfigMaps
change config maps
~~~bash
kubectl apply -f config-common.yaml
kubectl apply -f config-webapp.yaml
kubectl apply -f config-ai-service.yaml
~~~

## PVC
~~~bash
kubectl apply -f pvc.yaml
~~~

## StateFulSet
~~~bash
kubectl apply -f statefulset-mongodb.yaml
kubectl apply -f statefulset-qdrant.yaml
kubectl apply -f statefulset-redis.yaml
~~~

## copy cert and jwt folder to pvc
~~~bash
kubectl apply -f deployment-webapp.yaml
kubectl get pods -l app=sclab-webapp
kubectl cp ./cert <sclab-webapp-pod-name>:/data/cert
kubectl cp ./jwt <sclab-webapp-pod-name>:/data/jwt
kubectl rollout restart deployment/sclab-webapp
~~~

## Deployments
~~~bash
kubectl apply -f deployment-ai-service.yaml
kubectl apply -f deployment-gis-process.yaml
kubectl apply -f deployment-kafka-client.yaml
kubectl apply -f deployment-mqtt-broker.yaml
kubectl apply -f deployment-mqtt-client.yaml
~~~bash
