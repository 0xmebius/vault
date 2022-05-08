#! /bin/bash
set -e
set -o xtrace

#Example: bash -x setAAVE.sh file.config aave
. $1 # pass config file with relevant addresses as first argument
cd ..
cd ..
cd contracts
RPC="https://api.avax.network/ext/bc/C/rpc"
cast send --private-key $DEPLOYER $DEPLOYEDPROXY "setBOps(address)" $2 --rpc-url $RPC
cd ..
cd scripts/mainnet
