// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface ICRVGauge {
    function deposit(uint256 _value, address _addr, bool _claim_rewards) external;
    function withdraw(uint256 _value, bool _claim_rewards) external;
    function claim_rewards() external;
}