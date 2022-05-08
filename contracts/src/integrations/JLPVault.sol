// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {IMasterChef} from "src/interfaces/IMasterChef.sol";

/** 
 * @notice JLPVault is the vault token for UniV2 LP token reward tokens like Trader Joe LP tokens.
 * It collects rewards from the master chef farm and distributes them to the
 * swap so that it can autocompound. 
 */

contract JLPVault is Vault {

    uint256 public PID;
    IMasterChef public masterChef;
    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _masterChef,
    //     uint256 _PID
    // ) Vault(
    //     _underlying,
    //     _name,
    //     _symbol,
    //     _adminFee,
    //     _callerFee,
    //     _maxReinvestStale,
    //     _WAVAX
    // ) {
    //     masterChef = IMasterChef(_masterChef);
    //     PID = _PID;
    //     underlying.approve(_masterChef, MAX_INT);
    // }

    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _masterChef,
    //     uint256 _PID
    // ) {
    //     initialize(_underlying,
    //                 _name,
    //                 _symbol,
    //                 _adminFee,
    //                 _callerFee,
    //                 _maxReinvestStale,
    //                 _WAVAX,
    //                 _masterChef,
    //                 _PID);
    // }
    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _masterChef,
        uint256 _PID
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);

        masterChef = IMasterChef(_masterChef);
        PID = _PID;
        underlying.approve(_masterChef, MAX_INT);
    }
    
    function receiptPerUnderlying() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        return (1e18 * totalSupply) / masterChef.userInfo(PID, address(this)).amount;
    }

    function underlyingPerReceipt() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** underlyingDecimal;
        }
        return (1e18 * masterChef.userInfo(PID, address(this)).amount) / totalSupply;
    }
    
    function totalHoldings() public view override returns (uint256) {
        return masterChef.userInfo(PID, address(this)).amount;
    }

    function _triggerDepositAction(uint256 _amt) internal override {
        masterChef.deposit(PID, _amt);
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        masterChef.withdraw(PID, amtToReturn);
    }

    function _pullRewards() internal override {
        masterChef.deposit(PID, 0);
    }
}