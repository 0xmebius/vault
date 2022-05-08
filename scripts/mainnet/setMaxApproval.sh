#! /bin/bash
set -e
set -o xtrace

#Example: bash -x setAAVE.sh Vault token who
cd ..
cd ..
cd contracts
RPC="https://api.avax.network/ext/bc/C/rpc"
cast send --private-key $DEPLOYER $1 "setApprovals(address,address,uint256)" $2 $3 115792089237316195423570985008687907853269984665640564039457584007913129639935 --rpc-url $RPC
cd ..
cd scripts/mainnet
