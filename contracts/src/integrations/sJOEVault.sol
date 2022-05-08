// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {IStableJoeStaking} from "src/interfaces/IStableJoeStaking.sol";

/** 
 * @notice sJOEVault is the vault token for sJOE token rewards.
 * It collects rewards from the StableJoeStaking contract and distributes them to the
 * swap so that it can autocompound. 
 */

contract sJOEVault is Vault {

    IStableJoeStaking public sJOE;

    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _sJOE
    // ) Vault(
    //     _underlying,
    //     _name,
    //     _symbol,
    //     _adminFee,
    //     _callerFee,
    //     _maxReinvestStale,
    //     _WAVAX
    // ) {
    //     sJOE = IStableJoeStaking(_sJOE);
    //     underlying.approve(_sJOE, MAX_INT);
    // }

    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _sJOE
    // ) {
    //     initialize(_underlying,
    //                 _name,
    //                 _symbol,
    //                 _adminFee,
    //                 _callerFee,
    //                 _maxReinvestStale,
    //                 _WAVAX,
    //                 _sJOE);
    // }
    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _sJOE
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);

        sJOE = IStableJoeStaking(_sJOE);
        underlying.approve(_sJOE, MAX_INT);
    }

    function _preDeposit(uint256 _amt) internal override returns (uint256) {
        return _amt - ((_amt * sJOE.depositFeePercent()) / sJOE.DEPOSIT_FEE_PERCENT_PRECISION());
    }
    
    function receiptPerUnderlying() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        (uint256 _JoeAmt,) = sJOE.getUserInfo(address(this), address(0));
        return (1e18 * totalSupply) / _JoeAmt;
    }

    function underlyingPerReceipt() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** underlyingDecimal;
        }
        (uint256 _JoeAmt,) = sJOE.getUserInfo(address(this), address(0));
        return (1e18 * _JoeAmt) / totalSupply;
    }

    function totalHoldings() public view override returns (uint256) {
        (uint256 _JoeAmt,) = sJOE.getUserInfo(address(this), address(0));
        return _JoeAmt;
    }

    function _triggerDepositAction(uint256 _amt) internal override {
        sJOE.deposit(_amt);
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        sJOE.withdraw(amtToReturn);
    }

    function _pullRewards() internal override {
        sJOE.deposit(0);
    }
}