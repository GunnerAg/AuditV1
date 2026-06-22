#!/bin/bash

# Reinicia la red QBFT usando los datos ya existentes en QBFT-Network
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Comprueba que Docker estÃ¡ instalado y funcionando
if ! command -v docker &>/dev/null; then
  echo "Docker could not be found. Please install Docker and try again."
  exit 1
fi
if ! docker info &>/dev/null; then
  echo "Docker is not running. Please start Docker and try again."
  exit 1
fi

# carga parÃ¡metros desde config/qbftConfigFile.json
if [ ! -f "$SCRIPT_DIR/config/qbftConfigFile.json" ]; then
  echo "Missing config/qbftConfigFile.json. Run the installer first or place the file here."
  exit 1
fi

besuVersion=$(jq -r '.blockchain.nodes.besuVersion // "latest"' "$SCRIPT_DIR/config/qbftConfigFile.json")
num_nodes=$(jq -r '.blockchain.nodes.count // 4' "$SCRIPT_DIR/config/qbftConfigFile.json")
ip=$(jq -r '.blockchain.nodes.ip // "172.16.240"' "$SCRIPT_DIR/config/qbftConfigFile.json")


echo "Deteniendo y eliminando contenedores previos (si existen)..."
docker ps -a --filter "label=project=besu" -q | xargs -r docker stop || true
docker ps -a --filter "label=project=besu" -q | xargs -r docker rm || true

# Eliminar red antigua y crear red nueva con la subred configurada
if docker network inspect besu-network >/dev/null 2>&1; then
  echo "Eliminando la red Docker 'besu-network' existente..."
  docker network rm besu-network >/dev/null 2>&1 || true
fi

echo "Creando la red Docker 'besu-network' con subnet ${ip}.0/24"
if ! docker network inspect besu-network >/dev/null 2>&1; then
  if docker network create --driver=bridge --subnet=${ip}.0/24 besu-network >/dev/null 2>&1; then
    echo "Red 'besu-network' creada con subnet ${ip}.0/24"
  else
    echo "No se pudo crear la red con la subred ${ip}.0/24; intentando crear sin subnet..."
    if docker network create --driver=bridge besu-network >/dev/null 2>&1; then
      echo "Red 'besu-network' creada sin subnet explÃ­cita"
    else
      echo "Error: no se pudo crear la red Docker 'besu-network'. Redes Docker existentes:" 
      docker network ls
      exit 1
    fi
  fi
else
  echo "Red 'besu-network' ya existe."
fi

# Asegurarse de que existe QBFT-Network y que Node-1 tiene datos
if [ ! -d "$SCRIPT_DIR/QBFT-Network" ]; then
  echo "No se encontrÃ³ 'QBFT-Network' en el repositorio. Debe contener las carpetas Node-1..Node-N con los datos generados anteriormente."
  exit 1
fi
if [ ! -d "$SCRIPT_DIR/QBFT-Network/Node-1/data" ]; then
  echo "No se encontrÃ³ 'QBFT-Network/Node-1/data'. AsegÃºrese de que los datos de los nodos estÃ¡n presentes."
  exit 1
fi

# Asegurar que no existe contenedor con nombre bootnode
if docker ps -a --format '{{.Names}}' | grep -q '^bootnode$'; then
  docker stop bootnode >/dev/null 2>&1 || true
  docker rm bootnode >/dev/null 2>&1 || true
fi

echo "Iniciando bootnode..."

# La red se crea arriba con --subnet=${ip}.0/24, así que ${ip}.30 pertenece a esa subred.
# Evitamos python3 porque en Git Bash/Windows puede apuntar al alias roto de Microsoft Store.
network_subnet=$(docker network inspect besu-network | jq -r '.[0].IPAM.Config[0].Subnet // empty' 2>/dev/null || true)
desired_ip="${ip}.30"
if [[ "$network_subnet" == "${ip}.0/24" ]]; then
  echo "Usando IP estática para bootnode: $desired_ip"
  ip_flag="--ip $desired_ip"
else
  echo "Subnet inesperada '$network_subnet'; Docker asignará IP automáticamente."
  ip_flag=""
fi

CONFIG_DIR="$(cygpath -m "$SCRIPT_DIR/config")"
NODE1_DATA_DIR="$(cygpath -m "$SCRIPT_DIR/QBFT-Network/Node-1/data")"
PLUGINS_DIR="$(cygpath -m "$SCRIPT_DIR/plugins")"

MSYS2_ARG_CONV_EXCL="*" docker run -d --name bootnode \
  -v "$CONFIG_DIR:/opt/besu/config" \
  -v "$NODE1_DATA_DIR:/opt/besu/data" \
  -v "$PLUGINS_DIR:/opt/besu/plugins" \
  -p 30303:30303 \
  -p 8545:8545 \
  -p 9545:9545 \
  --label project=besu \
  --network besu-network \
  $ip_flag \
  hyperledger/besu:$besuVersion \
  --config-file=/opt/besu/config/configBootnode.toml >/dev/null

echo "Esperando a que el bootnode arranque..."
sleep 10

# Determinar la IP del bootnode: si usamos IP estÃ¡tica, la conocemos; si no, la consultamos al contenedor
if [[ -n "$ip_flag" ]]; then
  bootnode_ip="${ip}.30"
else
  bootnode_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' bootnode 2>/dev/null || true)
  if [[ -z "$bootnode_ip" ]]; then
    echo "Error: no se pudo determinar la IP del contenedor 'bootnode'. Comprueba 'docker ps' y los logs del contenedor."
    docker ps -a --filter "name=bootnode"
    exit 1
  fi
fi

# Obtener enode y preparar el fichero de validadores (getEnode.sh espera la IP del bootnode)
if [ -x "$SCRIPT_DIR/getEnode.sh" ]; then
  echo "Obteniendo enode desde el bootnode ($bootnode_ip)..."
  bash "$SCRIPT_DIR/getEnode.sh" $bootnode_ip
else
  echo "Advertencia: getEnode.sh no es ejecutable o no existe en el repo. Saltando la obtenciÃ³n automÃ¡tica del enode."
fi

# Lanzar nodos validadores usando el script existente
if [ -x "$SCRIPT_DIR/createValidatorNodes.sh" ]; then
  echo "Creando/arrancando nodos validadores (usando createValidatorNodes.sh)..."
  bash "$SCRIPT_DIR/createValidatorNodes.sh" "$besuVersion" "$num_nodes" "$ip"
else
  echo "Error: createValidatorNodes.sh no es ejecutable o no existe. No se pueden arrancar los validadores automÃ¡ticamente."
  exit 1
fi

echo "Red reiniciada. Comprueba 'docker ps' y los logs de los contenedores si es necesario."
