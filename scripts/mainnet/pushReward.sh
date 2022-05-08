#! /bin/bash
set -e
set -o xtrace

#Example: bash -x pushReward.sh file.config rewardToken
. $1 # pass config file with relevant addresses as first argument
cd ..
cd ..
cd contracts
RPC="https://api.avax.network/ext/bc/C/rpc"
cast send --private-key $DEPLOYER $DEPLOYEDPROXY "pushRewardToken(address)" $2 --rpc-url $RPC
cd ..
cd scripts/mainnet
