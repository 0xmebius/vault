// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "../interfaces/IStrategy.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * Test strategy that just transfers USDC in and out and does not deposit anywhere. 
 * The owner is the only one with control of this contract. 
 */

contract TestStrategyDummy is IStrategy, OwnableUpgradeable {

    IERC20 constant USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    address public PSM;

    function initialize(address _psm) external initializer {
        __Ownable_init();
        transferOwnership(_psm);
        PSM = _psm;
    }

    /// Deposit USDC into the strategy from the PSM
    function deposit(uint256 _amount) external override onlyOwner {
        USDC.transferFrom(PSM, address(this), _amount);
    }

    /// Withdraw USDC from the strategy from the PSM
    function withdraw(uint256 _amount) external override onlyOwner {
        USDC.transfer(PSM, _amount);
    }

    /// Total amount of USDC the contract owns. 
    function totalHoldings() external view override returns (uint256 _amount) {
        return USDC.balanceOf(address(this));
    }
}
