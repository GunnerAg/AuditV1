# ISBE LOCAL NETWORK ENVIRONMENT
**This document explains the basic operations for using the local isbe environment.**

## DESCRIPTION
This environment has been designed to enable the use of ISBE networks locally, allowing developers to manage the environment locally without depending on any remote, multi-user environment.

There are two ISBE networks:
- Networks based on secp256r1 signature
- Networks based on secp256k1 signature

Depending on the distribution that has been downloaded, one or the other will be used.

## REQUIREMENTS

To execute the scripts contained in this directory, you need the following:

- **Docker**: Must be installed and running
  - Verify installation: `docker --version`
  - Verify it's running: `docker info`

- **jq**: JSON processor for parsing configuration files
  - Install on Debian/Ubuntu: `apt-get install jq`
  - Install on macOS: `brew install jq`


## BASIC USAGE
Once the compressed file has been downloaded, we access the resulting directory:

To start:
```bash
./startNetwork.sh
```

Generate a network with 4 besu nodes by deploying Docker containers. 


To stop:
```bash
./stopNetwork.sh
```

