// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface ICompRewardController {
    function claimReward(uint8 rewardType, address payable holder) external;
}

