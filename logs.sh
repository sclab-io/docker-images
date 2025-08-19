#!/usr/bin/env bash

echo "Display logs"
echo "-------------------"
echo "docker"
echo "webapp"
echo "ai-service"
echo "db-agent"
echo "gis-process"
echo "kafka-client"
echo "mongo"
echo "redis"
echo "mqtt-broker"
echo "mqtt-client"
echo "node-vm-service"
echo "qdrant"
echo "nginx"
echo "-------------------"
read -p "Choose service [webapp]: " runEnv
runEnv=${runEnv:-webapp}

case ${runEnv} in

  "docker")
  docker compose logs -f --tail 100
  ;;

  "webapp")
  tail -n 100 -F ./data/webapp/logs/sclab.log
  ;;

  "gis-process")
  tail -n 100 -F ./data/gis-process/logs/sclab.log
  ;;

  "kafka-client")
  tail -n 100 -F ./data/kafka-client/logs/sclab.log
  ;;

  "mqtt-broker")
  tail -n 100 -F ./data/mqtt-broker/logs/sclab.log
  ;;

  "mqtt-client")
  tail -n 100 -F ./data/mqtt-client/logs/sclab.log
  ;;

  "ai-service")
  tail -n 100 -F ./data/ai-service/logs/debug/$(date +%F).log
  ;;

  "node-vm-service")
  tail -n 100 -F ./data/node-vm-service/logs/debug/$(date +%F).log
  ;;

  "db-agent")
  tail -n 100 -F ./data/db-agent/logs/debug/$(date +%F).log
  ;;

  "mongo")
  tail -n 100 -F ./data/mongo/logs/mongod.log
  ;;

  "redis")
  tail -n 100 -F ./data/redis/logs/redis-server.log
  ;;

  "nginx")
  tail -n 100 -F ./data/nginx/logs/access.log
  ;;

  "qdrant")
  docker logs qdrant -f -n 100
  ;;

esac

