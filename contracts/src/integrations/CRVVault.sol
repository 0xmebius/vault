// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {ICRVGauge} from "src/interfaces/ICRVGauge.sol";

/** 
 * @notice CRVVault is the vault token for CRV LP token rewards.
 * It collects rewards from the gauge and distributes them to the
 * swap so that it can autocompound. 
 */

contract CRVVault is Vault {

    ICRVGauge public gauge;

    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _gauge
    // ) Vault(
    //     _underlying,
    //     _name,
    //     _symbol,
    //     _adminFee,
    //     _callerFee,
    //     _maxReinvestStale,
    //     _WAVAX
    // ) {
    //     gauge = ICRVGauge(_gauge);
    //     underlying.approve(_gauge, MAX_INT);
    // }
    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _gauge
    // ) {
    //     initialize(_underlying,
    //                 _name,
    //                 _symbol,
    //                 _adminFee,
    //                 _callerFee,
    //                 _maxReinvestStale,
    //                 _WAVAX,
    //                 _gauge);
    // }
    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _gauge
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);

        gauge = ICRVGauge(_gauge);
        underlying.approve(_gauge, MAX_INT);
    }
    
    function receiptPerUnderlying() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        return (1e18 * totalSupply) / IERC20(address(gauge)).balanceOf(address(this));
    }

    function underlyingPerReceipt() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** underlyingDecimal;
        }
        return (1e18 * IERC20(address(gauge)).balanceOf(address(this))) / totalSupply;
    }

    function totalHoldings() public override view returns (uint256) {
        return IERC20(address(gauge)).balanceOf(address(this));
    }

    function _triggerDepositAction(uint256 _amt) internal override {
        gauge.deposit(_amt, address(this), true);
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        gauge.withdraw(amtToReturn, true);
    }

    function _pullRewards() internal override {
        gauge.claim_rewards();
    }
}