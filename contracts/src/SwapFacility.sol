// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {IxAnchor} from "src/interfaces/IxAnchor.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract SwapFacility is OwnableUpgradeable {

    uint256 internal constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    
    IxAnchor public immutable xAnchor;   
    AggregatorV3Interface public immutable priceFeed;
    ERC20 public immutable UST;
    ERC20 public immutable aUST;

    uint256 public swapFee;    
    mapping(address => bool) public canSwap;

    constructor(
        address _ust,
        address _aust,
        address _xanchor,
        address _pricefeed
    ) {
        initialize();
        canSwap[owner()] = true;

        UST = ERC20(_ust);
        aUST = ERC20(_aust);

        xAnchor = IxAnchor(_xanchor);
        priceFeed = AggregatorV3Interface(_pricefeed);
        aUST.approve(_xanchor, MAX_INT);
    }
    function initialize() internal initializer {
        __Ownable_init();
    }

    /* VIEW Funcs */

    /* Returns how much UST 1e18 aUST is worth */
    function _getUSTaUST() internal view returns (uint256) {
      (
        /*uint80 roundID*/,
        int256 price,
        /*uint256  startedAt*/,
        /*uint256  timeStamp*/,
        /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return uint256(price);
    }
    function getAmountIn(uint256 amountOut) public view returns (uint256 amtIn) {
        amtIn = 1e18 * amountOut / _getUSTaUST();
        amtIn = amtIn * 10000 / (10000 - swapFee);
    }
    function getAmountOut(uint256 amountIn) public view returns (uint256 amtOut) {
        amountIn -= amountIn * swapFee / 10000;
        amtOut = amountIn * _getUSTaUST() / 1e18;
    }

    /* SETTERS */

    function setFee(uint256 _fee) external onlyOwner {
        swapFee = _fee;
    }

    function setSwapper(address _swapper, bool _canSwap) external onlyOwner {
        canSwap[_swapper] = _canSwap;
    }

    function remove(uint256 _ustOut) external onlyOwner {
        SafeTransferLib.safeTransfer(UST, msg.sender, _ustOut);
    }


    /* SWAP */

    function swapAmountOut(uint256 amountOut) external returns (uint256 amountIn) {
        require(canSwap[msg.sender], "SF: Not approved to swap");
        require(UST.balanceOf(address(this)) > amountOut, "SF: Not enough UST");
        amountIn = getAmountIn(amountOut);
        SafeTransferLib.safeTransferFrom(aUST, msg.sender, address(this), amountIn);
        SafeTransferLib.safeTransfer(UST, msg.sender, amountOut);
        xAnchor.redeemStable(address(aUST), aUST.balanceOf(address(this)));
    }

    function swapAmountIn(uint256 amountIn) external returns (uint256 amountOut) {
        require(canSwap[msg.sender], "SF: Not approved to swap");
        amountOut = getAmountOut(amountIn);
        require(UST.balanceOf(address(this)) > amountOut, "SF: Not enough UST");
        SafeTransferLib.safeTransferFrom(aUST, msg.sender, address(this), amountIn);
        SafeTransferLib.safeTransfer(UST, msg.sender, amountOut);
        xAnchor.redeemStable(address(aUST), aUST.balanceOf(address(this)));
    }




}