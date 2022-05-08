pragma solidity ^0.8.0;

interface IJoePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(
        uint256 _amount0In,
        uint256 _amount1Out,
        address _to,
        bytes memory _data
    ) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}
