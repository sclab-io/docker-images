SCLAB Docker images
===================

# Quick reference

- **Maintained by**:  
  [SCLAB](https://github.com/sclab-io/docker-images)
- **Where to get help**:  
  [the Docker Community Forums](https://forums.docker.com/), [the Docker Community Slack](https://dockr.ly/slack), or [Stack Overflow](https://stackoverflow.com/search?tab=newest&q=docker)
- **Where to file issues**:  
  [https://github.com/sclab-io/docker-images/issues](https://github.com/sclab-io/docker-images/issues)
- **Source of this description**:  
  [docs repo's `sclab/` directory](https://github.com/sclab-io/docker-images/blob/master/README.md) ([history](https://github.com/sclab-io/docker-images/blob/master/history.md))
- **Developer documents**:
  [docs.sclab.io](https://docs.sclab.io)

# What is SCLAB?

Provides a platform to quickly build data visualizations by integrating all data into an all-in-one

> [www.sclab.io](https://www.sclab.io/)

![logo](https://avatars.githubusercontent.com/u/84428855?s=200&v=4)

# About this image

## SCLAB image list
* [sclabio/webapp](https://hub.docker.com/r/sclabio/webapp)
* [sclabio/gis-process](https://hub.docker.com/r/sclabio/gis-process)
* [sclabio/mqtt-client](https://hub.docker.com/r/sclabio/mqtt-client)
* [sclabio/mqtt-broker](https://hub.docker.com/r/sclabio/mqtt-broker)
* [sclabio/kafka-client](https://hub.docker.com/r/sclabio/kafka-client)
* [sclabio/ai-service](https://hub.docker.com/r/sclabio/ai-service)

## Other image list for running SCLAB images
* [mongo](https://hub.docker.com/_/mongo)
* [bytemark/smtp](https://hub.docker.com/r/bytemark/smtp)
* [bitnami/redis](https://hub.docker.com/r/bitnami/redis)
* [qdrant/qdrant](https://hub.docker.com/r/qdrant/qdrant)

You can not use this image without LICENSE KEY.
If you want to get one, please contact us. [support@sclab.io](mailto://support@sclab.io)

# Installation

## Pre-requirements

### OS

* os.linux.x86_64 (ubuntu, osx, linux)
* docker
* docker-compose

### Minimum system requirements

* Memory 8GB
* 40GB Free space

## Step 1. Install docker

* docker - [https://docs.docker.com/engine/install/](https://docs.docker.com/engine/install/)

## Step 2. Download files
~~~bash
$ git clone https://github.com/sclab-io/docker-images.git
~~~

| File Name          | Description                  |
|:-------------------|:-----------------------------|
| common.env         | Common Environment           |
| webapp.env         | Environment for webapp       |
| gis-process.env    | Environment for GIS Process  |
| mqtt-client.env    | Environment for MQTT Client  |
| mqtt-broker.env    | Environment for MQTT Broker  |
| kafka-client.env   | Environment for Kafka Client |
| ai-service.env     | Environment for AI service   |
| docker-compose.yml | Docker Compose YAML          |
| redis.conf         | Redis config                 |
| settings.json      | sclab settings               |
| run.sh             | run script                   |
| down.sh            | down script                  |
| logs.sh            | logs script                  |

## Step 3. Modify config files from this source
```bash
# ROOT_URL in common.env
# If you don't have domain for sclab, you need to add your custom domain to /etc/hosts file.
# ex) 127.0.0.1 yourdomain.com
$ vi common.env
# edit ROOT_URL
# ROOT_URL=http://yourdomain.com
# public.siteDomain from settings.json
# ex) yourdomain.com
$ vi settings.json
# edit siteDomain
# "public.siteDomain" : "yourdomain.com"
# "private.license": "your license code"
$ vi mqtt-broker.env
# edit SERVER_DOMAIN
# SERVER_DOMAIN=yourdomain.com
```

### common.env
| var                      | description                                                                                                                                                                                               |
|:-------------------------|:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| ROOT_URL                 | root url with your domain                                                                                                                                                                                 |
| HTTP_FORWARDED_COUNT     | The number of procedure servers in front of the service to properly check the IP address of the accessor.                                                                                                 |
| LOG_PATH                 | It is a log file path, and it does not need to be changed because it is an address to be used in the Docker image.                                                                                        |
| LOG_LEVEL                | Display log levels [error, warn, info, debug]                                                                                                                                                             |
| PORT                     | This is the default port number of the service, but it does not need to be changed because it is the port to be used within the Docker image. To change the actual port, change it in docker-compose.yml. |
| NODE_ENV                 | node js execution environment variable                                                                                                                                                                    |
| MONGO_URL                | Connection string for MongoDB                                                                                                                                                                             |
| MONGO_DB_READ_PREFERENCE | Read Preference for MongoDB                                                                                                                                                                               |
| MONGO_DB_POOL_SIZE       | Size of MongoDB connection pool                                                                                                                                                                           |
| METEORD_NODE_OPTIONS     | Options when running node. [nodejs options](https://nodejs.org/api/cli.html#cli_options)                                                                                                                  |
| NO_CUSTOM_LOG            | Set to 1 when you only console log                                                                                                                                                                        |
| MAIL_URL                 | Send mail server connection url (SMTP)                                                                                                                                                                    |
| QDRANT_CLUSTER_URL | QDRANT vector database cluster url |
| QDRANT_API_KEY | QDRANT vector database API Key |

### webapp.env
| var                | description                                        |
|:-------------------|:---------------------------------------------------|
| SERVER_ID          | ID used to distinguish when using multiple servers |
| ADD_INDEX          | Setting up mongodb index creation (1 - create)     |
| USE_HTTPS          | Use ssl (1 - use)                                  |
| SSL_KEY_PATH       | SSL key file path                                  |
| SSL_CERT_PATH      | SSL certification file path                        |
| SSL_PORT           | SSL port (443)                                     |
| SSL_TARGET_IP      | SSL ssl target ip (127.0.0.1)                      |
| SSL_TARGET_PORT    | SSL ssl target port (80)                           |
| FORCE_SSL          | http connection redirect to https (1 - use)        |
| IOT_JWT_KEY        | IOT JWT PRIVATE KEY file path                      |
| IOT_JWT_PUB_KEY    | IOT JWT PUBLIC KEY file path                       |
| API_JWT_KEY        | API JWT PRIVATE KEY file path                      |
| API_JWT_PUB_KEY    | API JWT PUBLIC KEY file path                       |
| SERVER_FILE_URL    | read file path for server side                     |

### gis-process.env
| var       | description                                                                                                                                          |
|:----------|:-----------------------------------------------------------------------------------------------------------------------------------------------------|
| SERVER_ID | Server ID is an ID used when parsing GIS files and storing them in DB. When duplicating using multiple servers, each server must use a different ID. |
| SERVER_FILE_URL | read file path for server side |

### mqtt-client.env
| var           | description               |
|:--------------|:--------------------------|
| SERVER_NAME   | MQTT client server name   |
| SERVER_DOMAIN | MQTT client server domain |
| SERVER_REGION | MQTT client server region |
| PUBLIC_IP     | public IP address         |
| PRIVATE_IP    | private IP address        |

### mqtt-broker.env
| var             | description                     |
|:----------------|:--------------------------------|
| SERVER_NAME     | MQTT broker server name         |
| SERVER_DOMAIN   | MQTT broker server domain       |
| SERVER_REGION   | MQTT broker server region       |
| PUBLIC_IP       | public IP address               |
| PRIVATE_IP      | private IP address              |
| JWT_KEY         | MQTT JWT Key file path (RS256)  |
| TLS_CERT        | certification file path for SSL |
| TLS_PRIVATE_KEY | private key file path for SSL   |

### kafka-client.env
| var           | description                 |
|:--------------|:----------------------------|
| SERVER_NAME   | Kafka client server name    |
| SERVER_DOMAIN | Kafka client server domain  |
| SERVER_REGION | Kafka client server region  |
| PUBLIC_IP     | public IP address           |
| PRIVATE_IP    | private IP address          |

### ai-service.env
| var           | description                 |
|:--------------|:----------------------------|
| OPENAI_KEY    | OpenAI api key              |
| REDIS_URL     | Redis server url            |
| AI_SERVER_ID  | AI Service ID for HA        |
| USE_AI_SERVICE | AI Service run flag ("1" / "") |
| IS_SYNC_SERVER | AI Data sync server flag (If you have multiple AI Service then only one server set "1") |
| USE_CHAT_SERVICE    | AI Chat Service flag          |
| SERVER_FILE_URL | read file path for server side |
| LOG_DIR | Log file path |
| NODE_OPTIONS | node options |
| ORIGIN | cors orgin |
| CREDENTIALS | CREDENTIALS flag ("true" / "") |
| PORT | AI Service REST API web service port |
| NODE_ENV | node environment |

### settings.json
| var                                                  | description                                                                                                                                                                                                                                                                                                             |
|:-----------------------------------------------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| public                                               | public settings (can access client and server)                                                                                                                                                                                                                                                                          |
| public.siteName                                      | site name                                                                                                                                                                                                                                                                                                               |
| public.siteDescription                               | site description                                                                                                                                                                                                                                                                                                        |
| public.defaultLanguage                               | default language (en, ko, es, hi, pt)                                                                                                                                                                                                                                                                                   |
| public.analyticsSettings.Google Analytics.trackingId | google analytics tracking id                                                                                                                                                                                                                                                                                            |
| public.storagePath                                   | storage file path                                                                                                                                                                                                                                                                                                       |
| public.pageSize                                      | default page size for single page                                                                                                                                                                                                                                                                                       |
| public.noImg                                         | no image url                                                                                                                                                                                                                                                                                                            |
| public.themeDefaultImg                               | theme default image url                                                                                                                                                                                                                                                                                                 |
| public.staticFilePath                                | static file path                                                                                                                                                                                                                                                                                                        |
| public.supportName                                   | support name for email                                                                                                                                                                                                                                                                                                  |
| public.supportEmail                                  | support email address                                                                                                                                                                                                                                                                                                   |
| public.siteDomain                                    | site domain (ex) yourdomain.com                                                                                                                                                                                                                                                                                         |
| public.mainPrefix                                    | used when the main prefix exists separately.<br />For example, if sclab.io is the domain and the editor domain is app.sclab.io<br />If the mainPrefix value is set to app, app.sclab.io becomes the main It becomes a domain<br /> and this address must match the domain used in ROOT_URL in the environment settings. |
| public.sso                                           | string array what you want to use. (google, facebook, kakao, naver)                                                                                                                                                                                                                                                     |
| public.useForceSSL                                   | force redirect http to https                                                                                                                                                                                                                                                                                            |
| public.uploadMaxMB                                   | max upload file size (MB)                                                                                                                                                                                                                                                                                               |
| public.editorHosts                                   | editor host array                                                                                                                                                                                                                                                                                                       |
| public.ai.chat | ai chat bot default prompt (If you don't want to use this ai feature, remove "public.ai" field.) |
| private                                              | private settings (only for server)                                                                                                                                                                                                                                                                                      |
| private.adminEmail                                   | admin email address - If admin account doesn't exists, then create admin account using this email address                                                                                                                                                                                                               |
| private.adminPassword                                | admin password when create admin account, you can change after login.                                                                                                                                                                                                                                                   |
| private.license                                      | sclab on-premise license code (required)                                                                                                                                                                                                                                                                                |
| private.sso.google.clientId                          | google client id for OAUTH                                                                                                                                                                                                                                                                                              |
| private.sso.google.secret                            | google secret for OAUTH                                                                                                                                                                                                                                                                                                 |
| private.sso.naver.clientId                           | naver client id for OAUTH                                                                                                                                                                                                                                                                                               |
| private.sso.naver.secret                             | naver secret for OAUTH                                                                                                                                                                                                                                                                                                  |
| private.sso.kakao.clientId                           | kakao client id for OAUTH                                                                                                                                                                                                                                                                                               |
| private.sso.kakao.secret                             | kakao secret for OAUTH                                                                                                                                                                                                                                                                                                  |
| private.sso.facebook.clientId                        | facebook client id for OAUTH                                                                                                                                                                                                                                                                                            |
| private.sso.facebook.secret                          | facebook secret for OAUTH                                                                                                                                                                                                                                                                                               |
| redisOplog                                           | redis connection information (only for server)                                                                                                                                                                                                                                                                          |
| redisOplog.redis.port                                | redis port                                                                                                                                                                                                                                                                                                              |
| redisOplog.redis.host                                | redis host                                                                                                                                                                                                                                                                                                              |
| redisOplog.redis.password                            | redis password                                                                                                                                                                                                                                                                                                          |
| redisOplog.retryIntervalMs                           | redis retry connection interval MS                                                                                                                                                                                                                                                                                      |
| redisOplog.mutationDefaults.optimistic               | Does not do a sync processing on the diffs. But it works by default with client-side mutations.                                                                                                                                                                                                                         |
| redisOplog.mutationDefaults.pushToRedis              | Pushes to redis the changes by default.                                                                                                                                                                                                                                                                                 |
| redisOplog.debug                                     | Will show timestamp and activity of redis-oplog.                                                                                                                                                                                                                                                                        |

## Step 4. create JWT key file for mqtt-broker
~~~bash
$ mkdir jwt
$ sudo ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwtRS256.key
# empty passphrase - just press enter
$ sudo openssl rsa -in ./jwt/jwtRS256.key -pubout -outform PEM -out ./jwt/jwtRS256.key.pub
~~~

## Step 5. create SSL key file for mqtt-broker
* If you have your own key file just use that key
~~~bash
$ mkdir cert
$ sudo openssl genrsa -out ./cert/privkey.pem 2048
$ sudo openssl req -new -sha256 -key ./cert/privkey.pem -out ./cert/csr.pem
$ sudo openssl x509 -req -in ./cert/csr.pem -signkey ./cert/privkey.pem -out ./cert/cert.pem
~~~

## Step 6. create JWT key file for SCLAB API
~~~bash
$ sudo ssh-keygen -t rsa -b 4096 -m PEM -f ./jwt/jwt-api-RS256.key
# empty passphrase - just press enter
$ sudo openssl rsa -in ./jwt/jwt-api-RS256.key -pubout -outform PEM -out ./jwt/jwt-api-RS256.key.pub
~~~

## Step 7. running instances
```bash
# create network
$ docker network create sclab-network
# running daemon mode
$ sudo ./run.sh
```
     Now you can access SCLAB Studio at http://yourdomain.com/ from your host system.
     After access SCLAB web page you have to login using admin account.
     Default account information is [admin@sclab.io / admin] from settings.json private.adminEmail, private.adminPassword.
     You can change your admin password from web page, don't need to change settings.json file private.adminPassword.

## Stop Running instance
```bash
$ sudo ./down.sh
```

## Display logs
```bash
$ sudo ./logs.sh
```

# License
Copyright (c) 2023 SCLAB All rights reserved.
