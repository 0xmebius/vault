// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IcToken {
    function exchangeRateCurrent() external returns (uint);
    function balanceOfUnderlying(address account) external returns (uint);
    function decimals() external view returns (uint);
}
