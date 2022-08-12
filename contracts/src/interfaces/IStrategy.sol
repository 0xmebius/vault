// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

// Interface for a USDC strategy, which has permissioned deposit 
// and withdraw functions and is only meant to interact with one 
// address. Used by Yeti Finance to earn yield on the USDC minted
// from the PSM.
// Deposit and withdraw functions must be onlyPSM. 
interface IStrategy {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function totalHoldings() external view returns (uint256 _amount);
}
