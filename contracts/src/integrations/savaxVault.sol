// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {sAVAX} from "src/interfaces/sAVAX.sol";

/** 
 * @notice compVault is the vault token for compound-like tokens such as Banker Joe jTokens and
 * Benqi qiTokens. It collects rewards from the rewardController and distributes them to the
 * swap so that it can autocompound. 
 */

contract savaxVault is Vault {

    uint256 public lastsAVAXUnderlyingBalance;    

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
        return lastsAVAXUnderlyingBalance;
    }

    function _getValueOfUnderlyingPost() internal override returns (uint256) {
        return sAVAX(address(underlying)).getPooledAvaxByShares(underlying.balanceOf(address(this)));
    }
    function totalHoldings() public override returns (uint256) {
        return sAVAX(address(underlying)).getPooledAvaxByShares(underlying.balanceOf(address(this)));
    }
    
    function _triggerDepositAction(uint256 amtToReturn) internal override {
        lastsAVAXUnderlyingBalance = sAVAX(address(underlying)).getPooledAvaxByShares(underlying.balanceOf(address(this)));
    }
    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        // Account for amount about to be removed since it hasn't been transferred out yet
        lastsAVAXUnderlyingBalance = sAVAX(address(underlying)).getPooledAvaxByShares(underlying.balanceOf(address(this)) - amtToReturn);
    }
    function _doSomethingPostCompound() internal override {
        // Function that uses comp token exchange rate to calculate the amount of cToken underlying tokens it has. Can't do this
        // in the _getValueOfUnderlyingPost call because this will be post fees are assessed. 
        lastsAVAXUnderlyingBalance = sAVAX(address(underlying)).getPooledAvaxByShares(underlying.balanceOf(address(this)));
    }
}
