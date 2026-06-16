#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
ZIP_PATH=""

usage() {
  cat <<'EOF'
Usage: ./importNetwork.sh -f <export.zip>

Options:
  -f, --file <zip>   Path to the exported network zip file (required)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      [[ $# -lt 2 ]] && { echo "Error: missing value for $1" >&2; exit 1; }
      ZIP_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -n "$ZIP_PATH" ]] || { echo "Error: zip file is required" >&2; usage; exit 1; }
[[ -f "$ZIP_PATH" ]] || { echo "Zip file not found: $ZIP_PATH" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "unzip is required but not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed" >&2; exit 1; }

read -r -p "This will stop/delete current Besu containers and replace config/QBFT-Network. Continue? [Y/n]: " reply
reply=${reply:-y}
if ! [[ "$reply" =~ ^[Yy]$ ]]; then
  echo "Aborted by user"
  exit 0
fi

containers=$(docker ps -a --filter "label=project=besu" -q)
if [[ -n "$containers" ]]; then
  echo "Stopping and removing existing Besu containers..."
  docker rm -f $containers >/dev/null
fi

if docker network inspect besu-network >/dev/null 2>&1; then
  echo "Removing previous Docker network besu-network..."
  docker network rm besu-network >/dev/null 2>&1 || true
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

unzip -q "$ZIP_PATH" -d "$tmp_dir"

for dir in config QBFT-Network plugins; do
  if [[ -e "$REPO_ROOT/$dir" ]]; then
    echo "Removing previous $dir"
    rm -rf "$REPO_ROOT/$dir"
  fi
done

copy_back() {
  local name=$1
  if [[ -d "$tmp_dir/$name" ]]; then
    echo "Restoring $name from archive"
    mv "$tmp_dir/$name" "$REPO_ROOT/$name"
  elif [[ "$name" == "plugins" ]]; then
    mkdir -p "$REPO_ROOT/plugins"
  else
    echo "Error: $name not found inside archive" >&2
    exit 1
  fi
}

copy_back config
copy_back QBFT-Network
copy_back plugins

if [[ -f "$tmp_dir/metadata.json" ]]; then
  mv "$tmp_dir/metadata.json" "$REPO_ROOT/metadata.json"
  echo "Metadata saved to metadata.json"
else
  echo "Archive does not include metadata.json (optional)."
fi

CONFIG_FILE="$REPO_ROOT/config/qbftConfigFile.json"
[[ -f "$CONFIG_FILE" ]] || { echo "Config file missing after import" >&2; exit 1; }

CHAIN_ID=$(jq -r '.genesis.config.chainId' "$CONFIG_FILE")
NODE_COUNT=$(jq -r '.blockchain.nodes.count' "$CONFIG_FILE")
BESU_VERSION=$(jq -r '.blockchain.nodes.besuVersion' "$CONFIG_FILE")
IP_BASE=$(jq -r '.blockchain.nodes.ip' "$CONFIG_FILE")

if [[ -z "$BESU_VERSION" || "$BESU_VERSION" == "null" ]]; then
  echo "Besu version missing in config" >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/QBFT-Network/Node-1/data"
mkdir -p "$REPO_ROOT/plugins"

echo "Creating Docker network besu-network (${IP_BASE}.0/24)..."
docker network create --driver=bridge --subnet=${IP_BASE}.0/24 besu-network >/dev/null 2>&1 || true

pushd "$REPO_ROOT" >/dev/null

echo "Starting bootnode container..."
docker run -d --name bootnode \
  -v "$(pwd)/config:/opt/besu/config" \
  -v "$(pwd)/QBFT-Network/Node-1/data:/opt/besu/data" \
  -v "$(pwd)/plugins:/opt/besu/plugins" \
  -p 30303:30303 \
  -p 8545:8545 \
  -p 9545:9545 \
  --label project=besu \
  --network besu-network \
  --ip ${IP_BASE}.30 \
  hyperledger/besu:$BESU_VERSION \
  --config-file=/opt/besu/config/configBootnode.toml >/dev/null

sleep 10
echo "Updating validator bootnodes..."
"$REPO_ROOT/getEnode.sh" ${IP_BASE}.30

echo "Launching validator nodes..."
"$REPO_ROOT/createValidatorNodes.sh" "$BESU_VERSION" "$NODE_COUNT" "$IP_BASE"

popd >/dev/null

echo "Import complete. Chain ID $CHAIN_ID running with $NODE_COUNT nodes."
