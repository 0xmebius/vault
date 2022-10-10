// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IPSM {
    function setStrategy(address _newStrategy) external;
    function setFeeRecipient(address _feeRecipient) external;
    function setDebtLimit(uint256 _newDebtLimit) external;
    function toggleRedeemPaused(bool _paused) external;
    function setFee(uint256 _newSwapFee) external;
    function redeemYUSD(uint256 _YUSDAmount, address _recipient) external returns (uint256 YUSDAmount);
    function mintYUSD(uint256 _USDCAmount, address _recipient) external returns (uint256 USDCAmount);
}
