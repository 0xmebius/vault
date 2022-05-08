#!/bin/bash
set -e
set -o xtrace
cd ..
cd ..
cd contracts
export FOUNDRY_OPTIMIZER_RUNS=1000000

export UST=0xb599c3590F42f8F995ECfa0f85D2980B76862fc1
export aUST=0xaB9A04808167C170A9EC4f8a87a0cD781ebcd55e
export xAnc=0x95aE712C309D33de0250Edd0C2d7Cb1ceAFD4550
export priceFeed=0x9D5024F957AfD987FdDb0a7111C8c5352A3F274c
RPC="https://api.avax.network/ext/bc/C/rpc"
# RPC="https://api.avax-test.network/ext/bc/C/rpc"
forge build --force
forge config
CREATION=$(forge create src/SwapFacility.sol:SwapFacility --rpc-url $RPC --private-key $DEPLOYER --constructor-args $UST $aUST $xAnc $priceFeed)
CONSTRUCTOR=$(cast abi-encode "constructor(address,address,address,address)" $UST $aUST $xAnc $priceFeed)
REG="(?:Deployed to: )((?:0x)[a-f0-9]{40})"
export DEPLOYED=$(echo "$CREATION" | pcregrep -o1 "$REG")
echo $DEPLOYED
forge flatten src/SwapFacility.sol > SwapFacility.txt
VERIFY=$(forge verify-contract --chain-id 43114 --constructor-args $CONSTRUCTOR --num-of-optimizations $FOUNDRY_OPTIMIZER_RUNS --compiler-version v0.8.10+commit.fc410830 $DEPLOYED src/SwapFacility.sol:SwapFacility $ETHERSCAN)
REG2="(?:GUID: \`)([a-z0-9]{50})\`$"
export GUID=$(echo "$VERIFY" | pcregrep -o1 "$REG2")
sleep 4
forge verify-check --chain-id 43114 $GUID $ETHERSCAN
cd ..
cd scripts/mainnet