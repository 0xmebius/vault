// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {ICompRewardController} from "src/interfaces/ICompRewardController.sol";
import {IcToken} from "src/interfaces/cToken.sol";

/** 
 * @notice compVault is the vault token for compound-like tokens such as Banker Joe jTokens and
 * Benqi qiTokens. It collects rewards from the rewardController and distributes them to the
 * swap so that it can autocompound. 
 */

contract compVault is Vault {

    ICompRewardController public rewardController;    
    IcToken public cToken;
    uint256 public lastCTokenUnderlyingBalance;    
    
    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _rewardController
    // ) Vault(
    //     _underlying,
    //     _name,
    //     _symbol,
    //     _adminFee,
    //     _callerFee,
    //     _maxReinvestStale,
    //     _WAVAX
    // ) {
    //     rewardController = ICompRewardController(_rewardController);
    //     cToken = IcToken(address(underlying));
    // }

    // constructor(
    //     address _underlying,
    //     string memory _name,
    //     string memory _symbol,
    //     uint256 _adminFee,
    //     uint256 _callerFee,
    //     uint256 _maxReinvestStale,
    //     address _WAVAX,
    //     address _rewardController
    // ) {
    //     initialize(_underlying,
    //                 _name,
    //                 _symbol,
    //                 _adminFee,
    //                 _callerFee,
    //                 _maxReinvestStale,
    //                 _WAVAX,
    //                 _rewardController);
    // }
    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _rewardController
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);

        rewardController = ICompRewardController(_rewardController);
        cToken = IcToken(address(underlying));
    }

    

    // Reward 0 = QI or JOE rewards
    // Reward 1 = WAVAX rewards
    function _pullRewards() internal override {
        rewardController.claimReward(0, payable(address(this)));
        rewardController.claimReward(1, payable(address(this)));
    }


    // |  Time frame            |  WCETH    |  CETH     |  ETH      |
    // |  Before                |  200      |  400      |  800      |
    // |  CETH autocompound     |  200      |  400      |  840      |
    // |  WCETH autocompound    |  200      |  420      |  882      |
    // |  10% Autocompound fee  |  N/A      |  -3.905   |  -8.2     |
    // |  Remaining balance     |  200      |  416.1    |  873.8    |
    // We have information Before and WCETH autocompound. The difference between the ETH balances in terms of CETH (current exchange rate) 
    // using ETH balance from Before and from "WCETH Autocompound" after is what we need to calculate the total gain and the fee can be 
    // taken a cut of the CETH amount. 
    // When this function is called, lastSavedCTokenUnderlyingBalance can be converted to current exchange rate CETH using the 
    // function cToken.exchangeRateCurrent(), so we return that adjusted value. 
    // Example run through here: 
    // lastSavedCTokenUnderlyingBalance, converted at the current CETH to ETH exchange ratio, is the old underlying balance, represented at 
    // the current value of CETH. In the table, this would be represented as (800 * 400/840) = (800 / currentExchangeRate) = 380.95. 20 CETH is bought from the fee autocompound, 
    // and this would be added to the current balance of CETH = 400 + 20 = 420. (420 - 380.95) * 0.1 = 3.905, which is the fee. 
    function _getValueOfUnderlyingPre() internal override returns (uint256) {
        return lastCTokenUnderlyingBalance;
    }

    function _getValueOfUnderlyingPost() internal override returns (uint256) {

        return cToken.balanceOfUnderlying(address(this));
    }
    function totalHoldings() public override returns (uint256) {
        return cToken.balanceOfUnderlying(address(this));
    }
    
    function _triggerDepositAction(uint256 amtToReturn) internal override {
        lastCTokenUnderlyingBalance = cToken.balanceOfUnderlying(address(this));
    }
    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        // Account for amount about to be removed since it hasn't been transferred out yet
        lastCTokenUnderlyingBalance = cToken.balanceOfUnderlying(address(this)) - ((amtToReturn * cToken.exchangeRateCurrent()) / 1e18);
    }
    function _doSomethingPostCompound() internal override {
        // Function that uses comp token exchange rate to calculate the amount of cToken underlying tokens it has. Can't do this
        // in the _getValueOfUnderlyingPost call because this will be post fees are assessed. 
        lastCTokenUnderlyingBalance = cToken.balanceOfUnderlying(address(this));
    }
}
