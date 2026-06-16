#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
CONFIG_DIR="$REPO_ROOT/config"
NETWORK_DIR="$REPO_ROOT/QBFT-Network"
PLUGINS_DIR="$REPO_ROOT/plugins"
EXPORT_DIR="$REPO_ROOT/exports"
OUTPUT_FILE=""

usage() {
  cat <<'EOF'
Usage: ./exportNetwork.sh [-f <zip-file>]

Options:
  -f, --file <zip>   Optional zip name (stored under exports/ if relative)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      [[ $# -lt 2 ]] && { echo "Error: missing value for $1" >&2; exit 1; }
      OUTPUT_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="besu-network-$(date +%Y%m%d-%H%M%S).zip"
fi

if [[ "$OUTPUT_FILE" != /* ]]; then
  OUTPUT_PATH="$EXPORT_DIR/$OUTPUT_FILE"
else
  OUTPUT_PATH="$OUTPUT_FILE"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "zip is required but not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed" >&2; exit 1; }

[[ -d "$CONFIG_DIR" ]] || { echo "config directory not found" >&2; exit 1; }
[[ -d "$NETWORK_DIR" ]] || { echo "QBFT-Network directory not found" >&2; exit 1; }

running_containers=$(docker ps --filter "label=project=besu" -q)
if [[ -n "$running_containers" ]]; then
  read -r -p "Running Besu containers detected. Stop them for a consistent export? [Y/n]: " answer
  answer=${answer:-y}
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Stopping running Besu containers..."
    docker stop $running_containers >/dev/null
  else
    echo "Continuing without stopping containers. Exported data may be inconsistent." >&2
  fi
fi

mkdir -p "$EXPORT_DIR"
TEMP_DIR=$(mktemp -d -p "$EXPORT_DIR" besu-export-XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

copy_dir() {
  local src=$1
  local dest=$2
  if [[ -d "$src" ]]; then
    echo "Copying $(basename "$src")..."
    cp -a "$src" "$dest"
  fi
}

copy_dir "$CONFIG_DIR" "$TEMP_DIR"
copy_dir "$NETWORK_DIR" "$TEMP_DIR"
copy_dir "$PLUGINS_DIR" "$TEMP_DIR"

CHAIN_ID=$(jq -r '.genesis.config.chainId' "$CONFIG_DIR/qbftConfigFile.json")
NODE_COUNT=$(jq -r '.blockchain.nodes.count' "$CONFIG_DIR/qbftConfigFile.json")
BESU_VERSION=$(jq -r '.blockchain.nodes.besuVersion' "$CONFIG_DIR/qbftConfigFile.json")
IP_BASE=$(jq -r '.blockchain.nodes.ip' "$CONFIG_DIR/qbftConfigFile.json")
BLOCK_PERIOD=$(jq -r '.genesis.config.qbft.blockperiodseconds' "$CONFIG_DIR/qbftConfigFile.json")
EPOCH_LENGTH=$(jq -r '.genesis.config.qbft.epochlength' "$CONFIG_DIR/qbftConfigFile.json")
EXPORT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "$TEMP_DIR/metadata.json" <<EOF
{
  "exportedAt": "$EXPORT_TS",
  "chainId": $CHAIN_ID,
  "nodeCount": $NODE_COUNT,
  "besuVersion": "$BESU_VERSION",
  "blockPeriodSeconds": $BLOCK_PERIOD,
  "epochLength": $EPOCH_LENGTH,
  "ipBase": "$IP_BASE"
}
EOF

(
  cd "$TEMP_DIR"
  zip -rq "$OUTPUT_PATH" .
)

echo "Network exported to $OUTPUT_PATH"
