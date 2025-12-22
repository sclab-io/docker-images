SCLAB Docker images
===================

# Quick reference

- **Maintained by**:  
  [SCLAB](https://github.com/sclab-io/docker-images)
- **Where to get help**:  
  [SCLAB Discord](https://discord.gg/KJqMvvR7dE) or Send email to <support@sclab.io>
- **Where to file issues**:  
  [https://github.com/sclab-io/docker-images/issues](https://github.com/sclab-io/docker-images/issues)
- **Source of this description**:  
  [docs repo's `sclab/` directory](https://github.com/sclab-io/docker-images/blob/master/README.md) ([history](https://docs.sclab.io/docs/history/SCLAB%20Studio%20OnPremise))
- **Developer documents**:
  [docs.sclab.io](https://docs.sclab.io)

# What is SCLAB?

SCLAB provides a platform to quickly build data visualizations by integrating all data into an all-in-one solution

> [www.sclab.io](https://www.sclab.io/)

![logo](https://avatars.githubusercontent.com/u/84428855?s=200&v=4)

# About this image

## SCLAB image list

- sclabio/webapp
- sclabio/gis-process
- sclabio/mqtt-client
- sclabio/mqtt-broker
- sclabio/kafka-client
- sclabio/node-vm-service
- sclabio/ai-service
- [sclabio/sclab-agent](https://hub.docker.com/r/sclabio/sclab-agent)

## Other image list for running SCLAB images

* [mongo](https://hub.docker.com/_/mongo)
- [bytemark/smtp](https://hub.docker.com/r/bytemark/smtp)
- [bitnami/redis](https://hub.docker.com/r/bitnami/redis)
- [qdrant/qdrant](https://hub.docker.com/r/qdrant/qdrant)
- [nginx](https://hub.docker.com/_/nginx)

# Installation

## Pre-requirements

### License code

You cannot use this image without a LICENSE KEY.
If you want to get one, please contact us. [support@sclab.io](mailto://support@sclab.io)

### AWS Credentials

AWS credentials are required to download SCLAB docker images.
These will be provided by SCLAB support along with your license key.
The installation script will prompt you to configure them.

### System Requirements

#### Hardware
- Memory: 8GB minimum
- Storage: 40GB free space minimum
- Architecture: x86_64 (AMD64)

#### Software
- Linux OS (see compatibility below)
- sudo/root access
- Basic Unix tools (automatically installed if missing)
- Docker (automatically installed if missing)
- AWS CLI (automatically installed if missing)

### Compatibility

The installation script is compatible with all major Linux distributions:

- **Ubuntu/Debian** and derivatives (Mint, Pop!_OS, etc.)
- **RHEL/CentOS/Fedora** and derivatives (Rocky Linux, AlmaLinux)
- **SUSE/openSUSE**
- **Arch Linux/Manjaro**
- **Alpine Linux**
- Other Linux distributions

## Step 1. Download files

```bash
git clone https://github.com/sclab-io/docker-images.git
cd docker-images
```

## Step 2. Run installation script

```bash
sudo ./install.sh
```

The installation script will:

1. **Check system compatibility** and requirements
   - Automatically installs Docker if not present (with your permission)
   - Installs missing dependencies (curl, sed, grep)
2. **Prompt for configuration**:
   - License key (required)
   - Database passwords (auto-generated if not provided)
   - OpenAI API key (optional - leave empty to use local Ollama models)
   - Editor subdomain prefix (optional - for hosting editor on separate subdomain)
   - Domain name (optional - leave empty for localhost)
   - Administrator email and password
3. **Configure all services** by updating configuration files
4. **Generate security keys** (JWT tokens and SSL certificates)
5. **Install dependencies** (AWS CLI for AWS ECR)
6. **Configure AWS credentials** (required for downloading SCLAB docker images)
7. **Create Docker network** for container communication

### Security Notes

- Auto-generated passwords are 32 characters, alphanumeric
- Admin password is stored in plain text in settings.json
- **⚠️ IMPORTANT: Change your admin password after first login!**

### Troubleshooting

If you encounter issues:
- Ensure you're running with sudo: `sudo ./install.sh`
- Make script executable if needed: `chmod +x install.sh`
- Check Docker is properly installed: `docker --version`
- For package manager issues, the script automatically detects and uses the appropriate one

### File list
| File Name              | Description                                |
|:-----------------------|:-------------------------------------------|
| common.env             | Common Environment                         |
| webapp.env             | Environment for webapp                     |
| gis-process.env        | Environment for GIS Process                |
| mqtt-client.env        | Environment for MQTT Client                |
| mqtt-broker.env        | Environment for MQTT Broker                |
| kafka-client.env       | Environment for Kafka Client               |
| ai-service.env         | Environment for AI service                 |
| node-vm-service.env    | Environment for Node VM service            |
| db-agent.env           | Environment for SCLAB Agent                |
| docker-compose.yml     | Docker Compose YAML                        |
| gen.yml                | Docker Compose YAML for key generation     |
| nginx.conf             | Nginx config                               |
| mongod.conf            | MongoDB configuration                      |
| settings.json          | SCLAB settings                             |
| install.sh             | Installation script                        |
| run.sh                 | Run script                                 |
| stop.sh                | Stop script                                |
| down.sh                | Down script                                |
| logs.sh                | Logs script                                |
| pull.sh                | Pull images script                         |
| update.sh              | Update webapp script                       |
| update-all.sh          | Update all services script                 |
| restart.sh             | Restart script                             |
| up.sh                  | Up script (alternative to run.sh)          |
| run.bat                | Windows run script                         |
| stop.bat               | Windows stop script                        |
| down.bat               | Windows down script                        |
| logs.bat               | Windows logs script                        |
| pull.bat               | Windows pull images script                 |
| update.bat             | Windows update webapp script               |
| update-all.bat         | Windows update all services script         |
| restart.bat            | Windows restart script                     |

### common.env

| var                      | description                                                                                                                                                                                               |
|:-------------------------|:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| ROOT_URL                 | root url with your domain                                                                                                                                                                                 |
| HTTP_FORWARDED_COUNT     | The number of proxy servers in front of the service to properly check the IP address of the client.                                                                                                       |
| LOG_PATH                 | Log file path. It does not need to be changed because it is an internal path used within the Docker image.                                                                                                |
| LOG_LEVEL                | Display log levels [error, warn, info, debug]                                                                                                                                                             |
| USE_FILE_LOG             | If you don't want to save log files, set to empty                                                                                                                                                         |
| LOG_FILE_COUNT           | A log file is created daily, and if set to 31, logs will be retained for 31 days.                                                                                                                         |
| PORT                     | This is the default port number of the service, but it does not need to be changed because it is the port to be used within the Docker image. To change the actual port, change it in docker-compose.yml. |
| NODE_ENV                 | Node.js execution environment variable                                                                                                                                                                    |
| MONGO_URL                | Connection string for MongoDB                                                                                                                                                                             |
| MONGO_DB_READ_PREFERENCE | Read Preference for MongoDB                                                                                                                                                                               |
| MONGO_DB_POOL_SIZE       | Size of MongoDB connection pool                                                                                                                                                                           |
| METEORD_NODE_OPTIONS     | Options when running Node.js. [Node.js options](https://nodejs.org/api/cli.html#cli_options)                                                                                                              |
| MAIL_URL                 | Mail server connection URL (SMTP)                                                                                                                                                                         |
| QDRANT_CLUSTER_URL       | Qdrant vector database cluster URL                                                                                                                                                                        |
| QDRANT_API_KEY           | Qdrant vector database API key                                                                                                                                                                            |
| OPENAI_KEY               | OpenAI API key                                                                                                                                                                                            |
| GEMINI_API_KEY           | Gemini API key                                                                                                                                                                                            |
| OLLAMA_API_HOST          | Ollama API host URL (<http://host:11434>)                                                                                                                                                                 |

### webapp.env

| var                         | description                                        |
|:----------------------------|:---------------------------------------------------|
| SERVER_ID                   | ID used to distinguish when using multiple servers |
| ADD_INDEX                   | Setting up MongoDB index creation (1 - create)     |
| IOT_JWT_KEY                 | IOT JWT PRIVATE KEY file path                      |
| IOT_JWT_PUB_KEY             | IOT JWT PUBLIC KEY file path                       |
| API_JWT_KEY                 | API JWT PRIVATE KEY file path                      |
| API_JWT_PUB_KEY             | API JWT PUBLIC KEY file path                       |
| SERVER_FILE_URL             | Read file path for server side                     |
| AUTO_PHOTO_SERVICE_INTERVAL | Photo service interval seconds (3600 = 1 Hour)     |

### gis-process.env

| var             | description                                                                                                                                          |
|:----------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------|
| SERVER_ID       | Server ID is an ID used when parsing GIS files and storing them in DB. When duplicating using multiple servers, each server must use a different ID. |
| SERVER_FILE_URL | Read file path for server side                                                                                                                       |

### mqtt-client.env

| var           | description               |
|:--------------|:--------------------------|
| SERVER_NAME   | MQTT client server name   |
| SERVER_DOMAIN | MQTT client server domain |
| SERVER_REGION | MQTT client server region |
| PUBLIC_IP     | Public IP address         |
| PRIVATE_IP    | Private IP address        |

### mqtt-broker.env

| var             | description                     |
|:----------------|:--------------------------------|
| SERVER_NAME     | MQTT broker server name         |
| SERVER_DOMAIN   | MQTT broker server domain       |
| SERVER_REGION   | MQTT broker server region       |
| PUBLIC_IP       | Public IP address               |
| PRIVATE_IP      | Private IP address              |
| JWT_KEY         | MQTT JWT Key file path (RS256)  |
| TLS_CERT        | Certificate file path for SSL   |
| TLS_PRIVATE_KEY | Private key file path for SSL   |

### kafka-client.env

| var           | description                 |
|:--------------|:----------------------------|
| SERVER_NAME   | Kafka client server name    |
| SERVER_DOMAIN | Kafka client server domain  |
| SERVER_REGION | Kafka client server region  |
| PUBLIC_IP     | public IP address           |
| PRIVATE_IP    | private IP address          |

### ai-service.env

| var                         | description                                                                             |
|:----------------------------|:----------------------------------------------------------------------------------------|
| REDIS_URL                   | Redis server url                                                                        |
| AI_SERVER_ID                | AI Service ID for HA                                                                    |
| USE_AI_SERVICE              | AI Service run flag ("1" / "")                                                          |
| IS_SYNC_SERVER              | AI Data sync server flag (If you have multiple AI Service then only one server set "1") |
| USE_CHAT_SERVICE            | AI Chat Service flag                                                                    |
| USE_SQL_GEN_SERVICE         | SQL Generator flag for union data ("1" / "")                                            |
| USE_AGENT_SERVICE           | AI Agent Service flag ("1" / "")                                                        |
| USE_AGENT_SERVICE_SCHEDULER | AI Agent Service Scheduler flag ("1" / "")                                              |
| USE_MCP_SERVICE             | MCP Service flag ("1" / "")                                                             |
| SERVER_FILE_URL             | read file path for server side                                                          |
| NODE_OPTIONS                | Node.js options                                                                         |
| ORIGIN                      | CORS origin                                                                             |
| CREDENTIALS                 | Credentials flag ("true" / "")                                                          |
| PORT                        | AI Service REST API web service port                                                    |
| NODE_ENV                    | Node.js environment                                                                     |
| HIDE_JSON                   | Hide JSON from chat message ("1" / "")                                                  |

### node-vm-service.env

| var                    | description              |
|:-----------------------|:-------------------------|
| LOG_DIR                | Log path                 |
| PORT                   | Port for node-vm-service |
| NODE_ENV               | Node.js environment      |
| LOG_LEVEL              | Log level                |
| ISOLATED_VM_TIMEOUT    | Timeout seconds          |
| ISOLATED_VM_MAX_MEMORY | Max memory MB            |

### db-agent.env

| var                           | description                       |
|:------------------------------|:----------------------------------|
| LOG_DIR                       | Log path                          |
| PORT                          | Port for SCLAB Agent              |
| NODE_ENV                      | Node.js environment               |
| LOG_LEVEL                     | Log level                         |
| SECRET_KEY                    | Secret key                        |
| JWT_PRIVATE_KEY_PATH          | JWT Private key path              |
| JWT_PUBLIC_KEY_PATH           | JWT public key path               |
| TLS_CERT                      | SSL public key file path          |
| TLS_KEY                       | SSL private key file path         |
| AGENT_DB_PATH                 | Agent database file path          |
| USE_MYBATIS                   | Use mybatis mapper                |
| ORACLE_CLIENT_DIR             | ORACLE Client DIR                 |
| MSSQL_IDLE_TIMEOUT_MS         | SQL Server idle time out ms       |
| TUNNEL_KEEP_ALIVE_INTERVAL_MS | SSH tunnel keep alive interval ms |

### settings.json

| var                                     | description                                                                                                                                                                                                                                                                                                             |
|:----------------------------------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| public                                  | Public settings (can access client and server)                                                                                                                                                                                                                                                                          |
| public.siteName                         | Site name                                                                                                                                                                                                                                                                                                               |
| public.siteDescription                  | Site description                                                                                                                                                                                                                                                                                                        |
| public.defaultLanguage                  | Default language (en, ko, es, hi, pt)                                                                                                                                                                                                                                                                                   |
| public.storagePath                      | Storage file path                                                                                                                                                                                                                                                                                                       |
| public.pageSize                         | Default page size for single page                                                                                                                                                                                                                                                                                       |
| public.noImg                            | No image URL                                                                                                                                                                                                                                                                                                            |
| public.themeDefaultImg                  | Theme default image URL                                                                                                                                                                                                                                                                                                 |
| public.staticFilePath                   | Static file path                                                                                                                                                                                                                                                                                                        |
| public.supportName                      | Support name for email                                                                                                                                                                                                                                                                                                  |
| public.supportEmail                     | Support email address                                                                                                                                                                                                                                                                                                   |
| public.siteDomain                       | Site domain (e.g., yourdomain.com)                                                                                                                                                                                                                                                                                      |
| public.mainPrefix                       | used when the main prefix exists separately.<br />For example, if sclab.io is the domain and the editor domain is app.sclab.io<br />If the mainPrefix value is set to app, app.sclab.io becomes the main It becomes a domain<br /> and this address must match the domain used in ROOT_URL in the environment settings. |
| public.sso                              | string array what you want to use. (google, facebook, kakao, naver)                                                                                                                                                                                                                                                     |
| public.useForceSSL                      | force redirect http to https                                                                                                                                                                                                                                                                                            |
| public.uploadMaxMB                      | max upload file size (MB)                                                                                                                                                                                                                                                                                               |
| public.editorHosts                      | editor host array                                                                                                                                                                                                                                                                                                       |
| public.ai.chat                          | ai chat bot default prompt (If you don't want to use this ai feature, remove "public.ai" field.)                                                                                                                                                                                                                        |
| public.ai.openai.llm                    | OpenAI LLM list array [{"model": "GPT5_MINI","label": "GPT5 mini"}]                                                                                                                                                                                                                                                     |
| public.ai.openai.embed                  | OpenAI embedding model list array [{"model": "text-embedding-3-large","label": "text-embedding-3-large (OPENAI)"}]                                                                                                                                                                                                      |
| public.ai.gemini.llm                    | Gemini LLM list array [{"model": "GEMINI_gemini-3-pro-preview","label": "Gemini 3 PRO"}]                                                                                                                                                                                                                                |
| public.ai.gemini.embed                  | Gemini embedding model list array [{"model": "GEMINI_gemini-embedding-001","label": "gemini-embedding-001 (Gemini)"}]                                                                                                                                                                                                   |
| public.ai.ollama.llm                    | Ollama LLM list array [{"model": "OLLAMA_gemma2:latest","label": "Gemma2 9B"}] you can use any Ollama models with prefix "OLLAMA_"                                                                                                                                                                                      |
| public.ai.ollama.embed                  | Ollama embedding model list array [{"model": "mxbai-embed-large","label": "mxbai-embed-large (OLLAMA)"}] current support model ("mxbai-embed-large")                                                                                                                                                                    |
| public.ai.ocrModels                     | ollama vlm model list array ["OLLAMA_qwen2.5vl:72b"] current support model ("qwen2.5")                                                                                                                                                                                                                                  |
| public.ai.sqlModel                      | model for SQL generation (e.g., "GPT5", "GPT4.1", "GEMINI_gemini-3-pro-preview", "OLLAMA_gemma2:latest")                                                                                                                                                                                                                |
| public.hub.llmAPI                       | "openai" (default), "gemini", "ollama"                                                                                                                                                                                                                                                                                  |
| private.adminEmail                      | admin email address - If admin account doesn't exists, then create admin account using this email address                                                                                                                                                                                                               |
| private.adminPassword                   | admin password when create admin account, you can change after login.                                                                                                                                                                                                                                                   |
| private.license                         | sclab on-premise license code (required)                                                                                                                                                                                                                                                                                |
| private.sso.google.clientId             | google client id for OAUTH                                                                                                                                                                                                                                                                                              |
| private.sso.google.secret               | google secret for OAUTH                                                                                                                                                                                                                                                                                                 |
| private.sso.naver.clientId              | naver client id for OAUTH                                                                                                                                                                                                                                                                                               |
| private.sso.naver.secret                | naver secret for OAUTH                                                                                                                                                                                                                                                                                                  |
| private.sso.kakao.clientId              | kakao client id for OAUTH                                                                                                                                                                                                                                                                                               |
| private.sso.kakao.secret                | kakao secret for OAUTH                                                                                                                                                                                                                                                                                                  |
| private.sso.facebook.clientId           | facebook client id for OAUTH                                                                                                                                                                                                                                                                                            |
| private.sso.facebook.secret             | facebook secret for OAUTH                                                                                                                                                                                                                                                                                               |
| private.cors                            | CORS header ("Access-Control-Allow-Origin")                                                                                                                                                                                                                                                                             |
| redisOplog                              | redis connection information (only for server)                                                                                                                                                                                                                                                                          |
| redisOplog.redis.port                   | redis port                                                                                                                                                                                                                                                                                                              |
| redisOplog.redis.host                   | redis host                                                                                                                                                                                                                                                                                                              |
| redisOplog.redis.password               | redis password                                                                                                                                                                                                                                                                                                          |
| redisOplog.retryIntervalMs              | redis retry connection interval MS                                                                                                                                                                                                                                                                                      |
| redisOplog.mutationDefaults.optimistic  | Does not do a sync processing on the diffs. But it works by default with client-side mutations.                                                                                                                                                                                                                         |
| redisOplog.mutationDefaults.pushToRedis | Pushes to redis the changes by default.                                                                                                                                                                                                                                                                                 |
| redisOplog.debug                        | Will show timestamp and activity of redis-oplog.                                                                                                                                                                                                                                                                        |

## Running SCLAB Studio

### Quick Command Reference

| Script          | Description                            | Usage                   |
|:----------------|:---------------------------------------|:------------------------|
| `install.sh`    | Initial installation and configuration | `sudo ./install.sh`     |
| `run.sh`        | Start all services                     | `sudo ./run.sh`         |
| `stop.sh`       | Stop all services (data preserved)     | `sudo ./stop.sh`        |
| `restart.sh`    | Restart all services                   | `sudo ./restart.sh`     |
| `logs.sh`       | View real-time logs                    | `sudo ./logs.sh`        |
| `down.sh`       | Stop and remove containers             | `sudo ./down.sh`        |
| `up.sh`         | Alternative start command              | `sudo ./up.sh`          |
| `pull.sh`       | Download latest images                 | `sudo ./pull.sh`        |
| `update.sh`     | Update webapp only                     | `sudo ./update.sh`      |
| `update-all.sh` | Update all services                    | `sudo ./update-all.sh`  |

### Start services

```bash
sudo ./run.sh
```

### Access SCLAB Studio

After starting, you can access SCLAB Studio at:
- **Local development**: https://127.0.0.1
- **Production**: https://yourdomain.com (or the domain you configured)
- **Editor** (if mainPrefix configured): https://editor.yourdomain.com

### Login

Use the administrator credentials that were displayed at the end of the installation:
- **Email**: The email you configured (default: admin@sclab.io)
- **Password**: The password you set or the auto-generated one

**⚠️ Important**: Change your password immediately after first login through the admin interface for security.  

## Managing SCLAB Studio

### Stop services

```bash
sudo ./stop.sh
```

Stops all running SCLAB Studio containers while preserving data.

### Restart services

```bash
sudo ./restart.sh
```

Restarts all SCLAB Studio services (equivalent to stop.sh followed by run.sh).

### View logs

```bash
sudo ./logs.sh
```

Displays real-time logs from all services. Press `Ctrl+C` to exit.

### Completely shutdown services

```bash
sudo ./down.sh
```

Stops and removes all containers. Data volumes are preserved.

### Start services (alternative)

```bash
sudo ./up.sh
```

Alternative to `run.sh`. Starts all services in detached mode.

## Updating SCLAB Studio

### Download latest images

```bash
sudo ./pull.sh
```

Downloads the latest versions of all SCLAB Studio Docker images without stopping services.

### Update webapp only

```bash
sudo ./update.sh
```

Updates only the webapp service:
1. Pulls the latest webapp image
2. Stops the webapp container
3. Restarts with the new image

Use this for quick webapp updates without affecting other services.

### Update all services

```bash
sudo ./update-all.sh
```

Updates all SCLAB Studio services:
1. Pulls all latest images
2. Stops all services
3. Restarts with new images

Use this when multiple services need updating or for major version upgrades.

## get db agent API token

```bash
sudo docker logs sclab-agent
```

## install ollama
[Ollama Install](./ollama/README.md)

## System diagram

![System Diagram](./img/System-Diagram.png)

## How to use Google SMTP server
- Make app password 
- [https://myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
- Change the MAIL_URL environment variable in the common.env file as follows.
- MAIL_URL=smtps://[GMAIL_ID]:[APP_PASSWORD]@smtp.gmail.com:465
- ex) MAIL_URL=smtps://yourname@gmail.com:abcdwxyz1234pqrs@smtp.gmail.com:465
- Change the public.supportEmail value in the settings.json as follows.
- supportEmail: "yourname@gmail.com"
- restart: sudo ./restart.sh

# License

Copyright (c) 2023 SCLAB All rights reserved.
