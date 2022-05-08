// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;


interface ISwapFacility {
    function swapAmountOut(uint256 amountOut) external returns (uint256 amountIn);
    function swapAmountIn(uint256 amountIn) external returns (uint256 amountOut);
    function getAmountOut(uint256 amountIn) external view returns (uint256 amtOut);

}