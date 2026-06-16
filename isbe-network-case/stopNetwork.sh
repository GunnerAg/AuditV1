#!/usr/bin/env bash

echo "Parando todos los nodos..."
docker stop $(docker ps --filter label=project=besu -q)

echo "Borrando los contenedores..."
docker rm $(docker ps --filter label=project=besu -a -q)

echo "ISBE Network parada"