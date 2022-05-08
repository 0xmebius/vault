// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IStableJoeStaking {

    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getUserInfo(address _user, address _rewardToken) external view returns (uint256, uint256);
    function DEPOSIT_FEE_PERCENT_PRECISION() external view returns (uint256);
    function depositFeePercent() external view returns (uint256);
}