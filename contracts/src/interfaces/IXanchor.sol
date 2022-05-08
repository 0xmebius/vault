// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IxAnchor {

    function depositStable(address token, uint256 amount) external;

    function claimRewards() external;

    function redeemStable(address token, uint256 amount) external;

    function withdrawAsset(string calldata token) external;

}