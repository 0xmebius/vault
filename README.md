# WrapMe 

A simple ERC20 wrapper interface to fungiblize liquidity mining incentives and autocompound rewards.

## Overview

Yield bearing tokens (i.e., Uni LP, 3crv, aTokens, etc.) are (obviously) fungible but as DeFi building blocks have increased in complexity, additional incentives provided to holders and stakers of yield bearing tokens often lose it's fungibility characteristics. This simple wrapper provides 3 primary features:

1) Static accounting of monotonically increasing rebasing tokens. (e.g., aTokens). This allows protocols to abstract out the additional accounting overhead of rebasing tokens into this wrapper contract.
2) Receiving external liquidity mining rewards beyond the base yield. This wrapper natively accepts rewards denominated in ERC20 tokens and native assets like ETH or WAVAX. This wrapper also provides a base implementation that allows arbitrary function calls to staking contracts to withdraw rewards into the wrapper.
3) Built in autocompounding of Reward Token -> Underlying Token. This wrapper inherits a naive router implementation that not only swaps base level ERC-20 assets across DEXs but also integrates the final step of converting a base ERC20 into the underlying yield bearing asset. It currently supports swaps into UniV2-like LP tokens, aTokens, Compound-like tokens and will support Curve LP tokens and more.

## Blueprint

```ml

contracts
└─ src
   ├─ Vault.sol — "Base implementation of the wrapper. Inherit this contract to implement custom integrations for calling rewards"
   ├─ VaultProxy.sol — "Simple proxy contract to inherit OpenZepplin's transparent upgradeable proxy"
   ├─ Router.sol — "Naive router implementation. Routes for each Reward Token -> Underlying need to be hardcoded upon deployment"
   ├─ Lever.sol — "Simple router inheritor to expose swapping functionality"
   ├─ SwapFacility.sol — "Simple centralized swap facility allowing for constant exchange rate swaps from aUST to UST"
   └─ integrations
      ├─ aaveVault.sol - "Adds additional functionality to claim rewards from AAVE Incentive controller. Also takes a cut from underlying yield"
      ├─ aaveV3Vault.sol - "Same as above but for AAVE V3"
      ├─ compVault.sol - "Adds additional functionality to claim rewards from Comptroller. Also takes a cut from underlying yield"
      ├─ CRVVault.sol - "Handles depositing and withdrawing from a liquidity gauge for CRV LP tokens"
      ├─ JLPVault.sol - "Handles depositing and withdrawal into Trader Joe MasterChef strategies"
      ├─ sJOEVault.sol - "Handles depositing and withdrawal into Trader Joe sJOE staking"
      ├─ savax.sol - "Handles depositing and withdrawal into Benqi's liquid AVAX staking"
      ├─ aUSTVault.sol - "Handles depositing and withdrawal into Anchor's UST strategy. This implementation allows for atomic deposits and withdrawals denominated in UST by making use of SwapFacility contract to do atomic aUST to UST swaps"
      └─ aUSTVaultV2.sol - "Handles depositing and withdrawal into Anchor's UST strategy. This implementation accepts deposits denominated in UST and withdrawals denominated in aUST. This means withdrawals are no longer limited by the liquidity in SwapFacility"

```

## Notice:
There are currently some issues with the accounting for aUSTVault and aUSTVaultV2 that result in a haircut for the users of the vault when race conditions occur. Essentially, when two or more users make a deposit during the period between a deposit and when the aUST lands in the vault contract from the bridge relayer, depositers recieve a few basis points of extra tokens due to the contract not knowing **exactly** how much aUST it actually recieved. It makes a pretty accurate guess using a Chainlink oracle to determine the exchange rate but it's not perfect. No risk of catastrophic loss, just bad UX as of now. Exploring various fixes currently.

**Install Foundry**
```https://github.com/gakonst/foundry```


**Building**
```
cd contracts
forge update
forge build
```

**Testing**
```
cd contracts
forge test --fork-url="https://api.avax.network/ext/bc/C/rpc" --fork-block-number=14578166
```

Match test case
```
--match-test testAltPoolPlatypusSwap
```

## License

[AGPL-3.0-only]

## Disclaimer

_These smart contracts are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the user interface or the smart contracts. They have not been audited and as such there can be no assurance they will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk._
