// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {IAaveRewardController} from "src/interfaces/IAaveRewardController.sol";

/** 
 * @notice aaveVault is the vault token for compound-like tokens such as Banker Joe jTokens and
 * Benqi qiTokens. It collects rewards from the rewardController and distributes them to the
 * swap so that it can autocompound. 
 */

contract aaveVault is Vault {

    IAaveRewardController public rewardController;

    // Store the previous aToken balance to calculate reward gain correctly. 
    uint256 public previousATokenBalance;
    address[] internal assetArr;

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
    //     rewardController = IAaveRewardController(_rewardController);
    //     assetArr = new address[](1);
    //     assetArr[0] = _underlying;
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
                    _WAVAX
                    );

        rewardController = IAaveRewardController(_rewardController);
        assetArr = new address[](1);
        assetArr[0] = _underlying;
    }

    // Pull wavax rewards
    function _pullRewards() internal override {
        rewardController.claimRewards(
            assetArr,
            rewardController.getRewardsBalance(assetArr, address(this)),
            address(this)
        );
    }


    // Returns the previous a token balance which is updated at the end of compound()
    function _getValueOfUnderlyingPre() internal override returns (uint256) {
        return previousATokenBalance;
    }

    // This returns the aToken balance after. It is the same as is implemented in Vault.sol but this is here for clarity. 
    // function _getValueOfUnderlyingPost() internal override returns (uint256) {
    //     return underlying.balanceOf(address(this));
    // }
    function _triggerDepositAction(uint256 amtToReturn) internal override {
        previousATokenBalance = underlying.balanceOf(address(this));
    }
    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        // Account for amount about to be removed since it hasn't been transferred out yet
        previousATokenBalance = underlying.balanceOf(address(this)) - amtToReturn;
    }

    function _doSomethingPostCompound() internal override {
        // Function that uses comp token exchange rate to calculate the amount of cToken underlying tokens it has. Can't do this
        // in the _getValueOfUnderlyingPost call because this will be post fees are assessed. 
        previousATokenBalance = underlying.balanceOf(address(this));
    }
}
