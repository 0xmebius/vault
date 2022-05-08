#! /bin/bash
#Example: bash -x upgradeProxy.sh PROXYADDRESS NEWLOGICADDRESS
cd ..
cd ..
cd contracts
IMPLEMENTATION=$2
PROXY=$1
RPC="https://api.avax.network/ext/bc/C/rpc"
cast send --private-key $DEPLOYER $PROXY "upgradeTo(address)" "${IMPLEMENTATION}" --rpc-url $RPC
cd ..
cd scripts/mainnet