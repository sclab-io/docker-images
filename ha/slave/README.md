SCLAB HA Master
===================

# Installation

## Pre-requirements

### License code

You can not use this image without LICENSE KEY.
If you want to get one, please contact us. [support@sclab.io](mailto://support@sclab.io)

### OS

* ubuntu
* docker
* docker-compose

### Minimum system requirements

* Memory 8GB
* 40GB Free space

## Step 1. Install docker

* docker - [https://docs.docker.com/engine/install/](https://docs.docker.com/engine/install/)

## Step 2. Download files

~~~bash
git clone https://github.com/sclab-io/docker-images.git
~~~

## Step 3. Modify config files from this source

### edit setup.sh

* change server ip address and domain

~~~bash
vi ../setup.sh

# change site domain
# add license code
vi settings.json
~~~

## Step 4. NFS setup

~~~bash
./setup-nfs-client.sh
~~~

* empty passphrase - just press enter

## Step 5. Install AWS CLI

[https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

### linux install

~~~bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
~~~

~~~bash
unzip awscliv2.zip
~~~

~~~bash
sudo ./aws/install
~~~

## Step 6. AWS Configure

* add AWS Access Key ID and AWS Secret Access Key from SCLAB

~~~bash
sudo aws configure
~~~

## Step 7. running instances

### create network

```bash
sudo docker network create sclab-network
```

### running daemon mode

```bash
sudo ./run.sh
```

Now you can access SCLAB Studio at <http://yourdomain.com/> from your host system.  
After access SCLAB web page you have to login using admin account.  
Default account information is [admin@sclab.io / admin] from settings.json private.adminEmail, private.adminPassword.  
You can change your admin password from web page, don't need to change settings.json file private.adminPassword.  

## Stop Running instance

```bash
sudo ./down.sh
```

## Display logs

```bash
sudo ./logs.sh
```

## Download new images

```bash
sudo ./pull.sh
```

## Update all images

```bash
sudo ./update-all.sh
```

## Update images and restart webapp

If any service other than the webapp is updated, please use "./update-all.sh".

```bash
sudo ./update.sh
```

# License

Copyright (c) 2024 SCLAB All rights reserved.
