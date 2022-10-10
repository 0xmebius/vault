// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IBurner {
    function burn(address _account, uint256 _amount) external;
}
