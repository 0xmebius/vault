#!/bin/bash
set -e
set -o xtrace
cd ..
cd ..
cd contracts
export FOUNDRY_OPTIMIZER_RUNS=1000000
RPC="https://api.avax.network/ext/bc/C/rpc"
# RPC="https://api.avax-test.network/ext/bc/C/rpc"

PSM=0x3f97403218b71aa1ff2678e28398038a5c24641d

forge build --force
forge config
CREATION=$(forge create src/integrations/aUSDCPSMStrategy.sol:aUSDCPSMStrategy --rpc-url $RPC --private-key $DEPLOYER --constructor-args $PSM --verify)
REG="(?:Deployed to: )((?:0x)[a-f0-9]{40})"
export DEPLOYED=$(echo "$CREATION" | pcregrep -o1 "$REG")
echo $DEPLOYED
forge flatten src/integrations/aUSDCPSMStrategy.sol > aUSDCPSMStrategy.txt

# VERIFY=$(forge verify-contract --chain-id 43114 --num-of-optimizations $FOUNDRY_OPTIMIZER_RUNS --constructor-args $PSM --compiler-version v0.8.10+commit.fc410830 $DEPLOYED src/integrations/aUSDCPSMStrategy.sol:aUSDCPSMStrategy $ETHERSCAN)
REG2="(?:GUID: \`)([a-z0-9]{50})\`$"
export GUID=$(echo "$DEPLOYED" | pcregrep -o1 "$REG2")
sleep 4
forge verify-check --chain-id 43114 $GUID $ETHERSCAN
cd ..
cd scripts/mainnet
