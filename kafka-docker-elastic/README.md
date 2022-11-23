# Setup
~~~bash
$ mkdir -p ./data/kafka-connect/plugins
$ cp ./elastic-source-connect-1.5.2-jar-with-dependencies.jar ./data/kafka-connect/plugins

# start docker compose
$ docker compose up
# or daemon mode
$ docker compose up -d
~~~