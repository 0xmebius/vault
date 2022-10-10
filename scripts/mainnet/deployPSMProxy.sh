#! /bin/bash
set -e
set -o xtrace
#Example: bash deployPSMProxy.sh PSM.config
. $1 # pass config file with relevant addresses as first argument
cd ..
cd ..
cd contracts
export FOUNDRY_OPTIMIZER_RUNS=1000000
# forge build --force
INITCALLDATA=$(cast calldata \
"$INITSIGNATURE" \
$BURNER \
$STRATEGY \
$FEERECIPIENT \
$LIMIT \
$SWAPFEE)

RPC="https://api.avax.network/ext/bc/C/rpc"
# RPC="https://api.avax-test.network/ext/bc/C/rpc"
CONSTRUCTOR=$(cast abi-encode "constructor(address,address,bytes memory)" $IMPLEMENTATION $ADMIN $INITCALLDATA)
CREATION=$(forge create src/Proxy.sol:Proxy --rpc-url $RPC --private-key $DEPLOYER \
--constructor-args \
$IMPLEMENTATION \
$ADMIN \
$INITCALLDATA)
REG="(?:Deployed to: )((?:0x)[a-f0-9]{40})"
export DEPLOYEDPROXY=$(echo "$CREATION" | pcregrep -o1 "$REG")
echo $DEPLOYEDPROXY
forge flatten src/Proxy.sol > Proxy.txt
VERIFY=$(forge verify-contract --chain-id 43114 --num-of-optimizations $FOUNDRY_OPTIMIZER_RUNS --compiler-version v0.8.10+commit.fc410830 $DEPLOYEDPROXY --constructor-args $CONSTRUCTOR src/Proxy.sol:Proxy $ETHERSCAN)
REG2="(?:GUID: \`)([a-z0-9]{50})\`$"
export GUID=$(echo "$VERIFY" | pcregrep -o1 "$REG2")
forge verify-check --chain-id 43114 $GUID $ETHERSCAN
cd ..
cd scripts/mainnet
printf "\nDEPLOYEDPROXY=$DEPLOYEDPROXY\n">> $1
# printf "CONSTRUCTOR=$CONSTRUCTOR">> $1
# echo $CONSTRUCTOR
