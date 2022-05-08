// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface sAVAX {
    function getPooledAvaxByShares(uint256) external returns (uint256);
    function balanceOf(address account) external returns (uint);
    function decimals() external view returns (uint);
}
