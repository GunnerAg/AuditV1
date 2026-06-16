#!/bin/bash

BESU_VERSION=$1 # Besu version to use
NUM_VALIDATORS=$2  # Total number of validator nodes
BASE_IP=$3 # Base IP address for the network (e.g., 172.16.240)
NETWORK_NAME="besu-network" 


# Create Docker network if it does not exist
docker network inspect $NETWORK_NAME >/dev/null 2>&1 || \
docker network create --driver=bridge --subnet=$BASE_IP.0/24 $NETWORK_NAME

# Determine if the existing network has a configured subnet, and capture it
network_subnet=$(docker network inspect $NETWORK_NAME | jq -r '.[0].IPAM.Config[0].Subnet // empty' 2>/dev/null || true)
if [[ -n "$network_subnet" ]]; then
  echo "Network '$NETWORK_NAME' has subnet: $network_subnet"
else
  echo "Network '$NETWORK_NAME' has no user-configured subnet; Docker will assign IPs automatically."
fi

# Loop through validator nodes 
for ((i = 2; i <= NUM_VALIDATORS; i++)); do
  NODE_NAME="node$i"
  NODE_DIR="QBFT-Network/Node-$i/data"
  mkdir -p "$NODE_DIR"

  PORT_OFFSET=$((i - 1))
  P2P_PORT=$((30304 + PORT_OFFSET))
  RPC_PORT=$((8545 + PORT_OFFSET))
  METRICS_PORT=$((9546 + PORT_OFFSET))
  NODE_IP="$BASE_IP.$((30 + PORT_OFFSET))"

  # Decide whether to pass --ip depending on whether NODE_IP belongs to network_subnet
  ip_flag=""
  if [[ -n "$network_subnet" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      if python3 -c "import ipaddress,sys; sys.exit(0) if ipaddress.ip_address('$NODE_IP') in ipaddress.ip_network('$network_subnet') else sys.exit(1)"; then
        ip_flag="--ip $NODE_IP"
      else
        echo "Desired IP $NODE_IP does not belong to network subnet $network_subnet; not using --ip for $NODE_NAME."
        ip_flag=""
      fi
    else
      echo "python3 not available; skipping IP membership check. Not using --ip for $NODE_NAME."
      ip_flag=""
    fi
  else
    echo "Network has no user-configured subnet; not using --ip for $NODE_NAME."
    ip_flag=""
  fi

  echo "Starting $NODE_NAME with desired IP $NODE_IP and ports: P2P=$P2P_PORT, RPC=$RPC_PORT, METRICS=$METRICS_PORT"

  docker run -d --name $NODE_NAME \
    -v "$(pwd)/config:/opt/besu/config" \
    -v "$(pwd)/QBFT-Network/Node-$i/data:/opt/besu/data" \
    -v "$(pwd)/plugins:/opt/besu/plugins" \
    -p $P2P_PORT:$P2P_PORT \
    -p $RPC_PORT:$RPC_PORT \
    -p $METRICS_PORT:$METRICS_PORT \
    --label project=besu \
    --network $NETWORK_NAME \
    $ip_flag \
    hyperledger/besu:$BESU_VERSION \
    --config-file=/opt/besu/config/configValidators.toml \
    --p2p-port=$P2P_PORT \
    --rpc-http-port=$RPC_PORT \
    --metrics-port=$METRICS_PORT

  # If Docker assigned IP dynamically, report the assigned IP
  if [[ -z "$ip_flag" ]]; then
    assigned_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $NODE_NAME 2>/dev/null || true)
    echo "$NODE_NAME assigned IP: ${assigned_ip:-(unknown)}"
  fi
done

# Generate explorer config deterministically from NUM_VALIDATORS
EXPLORER_CONFIG="explorer/src/config/config.json"

echo "Generating $EXPLORER_CONFIG for $NUM_VALIDATORS validators"

nodes_json=""

# Node-1 as bootnode
nodes_json="{\"name\": \"bootnode\", \"client\": \"besu\", \"rpcUrl\": \"http://127.0.0.1:8545\", \"privateTxUrl\": \"\"}"

# Remaining nodes as node1..nodeN-1
if [ "$NUM_VALIDATORS" -ge 2 ]; then
  for ((i = 1; i <= (NUM_VALIDATORS - 1); i++)); do
    idx=$((i + 1))
    rpc_port=$((8545 + i))
    entry="{\"name\": \"node$idx\", \"client\": \"besu\", \"rpcUrl\": \"http://127.0.0.1:$rpc_port\", \"privateTxUrl\": \"\"}"
    nodes_json="$nodes_json, $entry"
  done
fi

mkdir -p "$(dirname "$EXPLORER_CONFIG")"
cat > "$EXPLORER_CONFIG" <<EOF
{
  "algorithm": "qbft",
  "nodes": [
    $nodes_json
  ]
}
EOF

echo "Explorer config written to $EXPLORER_CONFIG"
