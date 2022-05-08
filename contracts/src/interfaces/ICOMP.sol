pragma solidity ^0.8.0;

interface ICOMP {
    function redeem(uint redeemTokens) external returns (uint);
    function mint(uint mintAmount) external returns (uint);
    function mint() external payable;
    function underlying() external view returns (address);
}