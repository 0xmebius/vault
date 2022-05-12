// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IAAVE, IAAVEV3} from "./interfaces/IAAVE.sol";
import {ICOMP} from "./interfaces/ICOMP.sol";
import {IJoePair} from "./interfaces/IJoePair.sol";
import {IMeta} from "./interfaces/IMeta.sol";
import {IJoeRouter} from "./interfaces/IJoeRouter.sol";
import {IPlainPool, ILendingPool, IMetaPool} from "./interfaces/ICurvePool.sol";
import {IYetiVaultToken} from "./interfaces/IYetiVaultToken.sol";
import {IWAVAX} from "./interfaces/IWAVAX.sol";
import {IPlatypusPool} from "./interfaces/IPlatypusPool.sol";

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/** 
 * @notice Router is a contract for routing token swaps through various defined routes. 
 * It takes a modular approach to swapping and can go through multiple routes, as encoded in the 
 * Node array which corresponds to a route. A path is defined as routes[fromToken][toToken]. 
 */

contract Router is OwnableUpgradeable {
    using SafeTransferLib for IERC20;

    address public traderJoeRouter;
    address public aaveLendingPool;
    event RouteSet(address fromToken, address toToken, Node[] path);
    event Swap(
        address caller,
        address startingTokenAddress,
        address endingTokenAddress,
        uint256 amount,
        uint256 minSwapAmount,
        uint256 actualOut
    );
    uint256 internal constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 internal constant FEE_DENOMINATOR = 1e3;
    uint256 internal constant FEE_COMPLIMENT = 997;

    // nodeType
    // 1 = Trader Joe Swap
    // 2 = Joe LP Token
    // 3 = curve pool
    // 4 = convert between native balance and ERC20
    // 5 = comp-like Token for native
    // 6 = aave-like Token
    // 7 = comp-like Token
    struct Node {
        // Is Joe pair or cToken etc. 
        address protocolSwapAddress;
        uint256 nodeType;
        address tokenIn;
        address tokenOut;
        int128 _misc; //Extra info for curve pools
        int128 _in;
        int128 _out;
    }

    // Usage: path = routes[fromToken][toToken]
    mapping(address => mapping(address => Node[])) public routes;

    // V2 add WAVAX constant variable
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    // V3 add AAVEV3 Lending Pool (decremented __gap from 49 -> 48)
    address public aaveLendingPoolV3;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;

    function setJoeRouter(address _traderJoeRouter) public onlyOwner {
        traderJoeRouter = _traderJoeRouter;
    }

    function setAAVE(address _aaveLendingPool, address _aaveLendingPoolV3) public onlyOwner {
        aaveLendingPool = _aaveLendingPool;
        aaveLendingPoolV3 = _aaveLendingPoolV3;
    }

    function setApprovals(
        address _token,
        address _who,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).approve(_who, _amount);
    }

    function setRoute(
        address _fromToken,
        address _toToken,
        Node[] calldata _path
    ) external onlyOwner {
        delete routes[_fromToken][_toToken];
        for (uint256 i = 0; i < _path.length; i++) {
            routes[_fromToken][_toToken].push(_path[i]);
        }
        // routes[_fromToken][_toToken] = _path;
        emit RouteSet(_fromToken, _toToken, _path);
    }

    //////////////////////////////////////////////////////////////////////////////////
    // #1 Swap through Trader Joe
    //////////////////////////////////////////////////////////////////////////////////
    function swapJoePair(
        address _pair,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal returns (uint256) {
        
        SafeTransferLib.safeTransfer(ERC20(_tokenIn), _pair, _amountIn);
        uint256 amount0Out;
        uint256 amount1Out;
        (uint256 reserve0, uint256 reserve1, ) = IJoePair(_pair).getReserves();
        if (_tokenIn < _tokenOut) {
            // TokenIn=token0
            amount1Out = _getAmountOut(_amountIn, reserve0, reserve1);
        } else {
            // TokenIn=token1
            amount0Out = _getAmountOut(_amountIn, reserve1, reserve0);
        }
        IJoePair(_pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            new bytes(0)
        );
        return amount0Out != 0 ? amount0Out : amount1Out;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(_amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            _reserveIn > 0 && _reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = _amountIn * FEE_COMPLIMENT;
        uint256 numerator = amountInWithFee * _reserveOut;
        uint256 denominator = (_reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    //////////////////////////////////////////////////////////////////////////////////
    // #2 Swap into and out of Trader Joe LP Token
    //////////////////////////////////////////////////////////////////////////////////

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function _getAmtToSwap(uint256 r0, uint256 totalX)
        internal
        pure
        returns (uint256)
    {
        // For optimal amounts, this quickly becomes an algebraic optimization problem
        // You must account for price impact of the swap to the corresponding token
        // Optimally, you swap enough of tokenIn such that the ratio of tokenIn_1/tokenIn_2 is the same as reserve1/reserve2 after the swap
        // Plug _in the uniswap k=xy equation _in the above equality and you will get the following:
        uint256 sub = (r0 * 998500) / 994009;
        uint256 toSqrt = totalX * 3976036 * r0 + r0 * r0 * 3988009;
        return (FixedPointMathLib.sqrt(toSqrt) * 500) / 994009 - sub;
    }

    function _getAmountPairOut(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut,
        uint256 _totalSupply
    ) internal view returns (uint256 amountOut) {
        // Given token, how much lp token will I get?

        _amountIn = _getAmtToSwap(_reserveIn, _amountIn);
        uint256 amountInWithFee = _amountIn * FEE_COMPLIMENT;
        uint256 numerator = amountInWithFee * _reserveOut;
        uint256 denominator = _reserveIn * FEE_DENOMINATOR + amountInWithFee;
        uint256 _amountIn2 = numerator / denominator;
        // https://github.com/traderjoe-xyz/joe-core/blob/11d6c6a57017b5f890eb7ea3e3a61de245a41ef2/contracts/traderjoe/JoePair.sol#L153
        amountOut = _min(
            (_amountIn * _totalSupply) / (_reserveIn + _amountIn),
            (_amountIn2 * _totalSupply) / (_reserveOut - _amountIn2)
        );
    }

    function _getAmountPairIn(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut,
        uint256 _totalSupply
    ) internal view returns (uint256 amountOut) {
        // Given lp token, how much token will I get?
        uint256 amt0 = (_amountIn * _reserveIn) / _totalSupply;
        uint256 amt1 = (_amountIn * _reserveOut) / _totalSupply;

        _reserveIn = _reserveIn - amt0;
        _reserveOut = _reserveOut - amt1;

        uint256 amountInWithFee = amt0 * FEE_COMPLIMENT;
        uint256 numerator = amountInWithFee * _reserveOut;
        uint256 denominator = (_reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
        amountOut = amountOut + amt1;
    }

    function swapLPToken(
        address _token,
        address _pair,
        uint256 _amountIn,
        bool _LPIn
    ) internal returns (uint256) {
        address token0 = IJoePair(_pair).token0();
        address token1 = IJoePair(_pair).token1();
        if (_LPIn) {
            IJoeRouter(traderJoeRouter).removeLiquidity(
                token0,
                token1,
                _amountIn,
                0,
                0,
                address(this),
                block.timestamp
            );
            if (token0 == _token) {
                swapJoePair(
                    _pair,
                    token1,
                    token0,
                    IERC20(token1).balanceOf(address(this))
                );
            } else if (token1 == _token) {
                swapJoePair(
                    _pair,
                    token0,
                    token1,
                    IERC20(token0).balanceOf(address(this))
                );
            } else {
                revert("tokenOut is not a token _in the pair");
            }
            return IERC20(_token).balanceOf(address(this));
        } else {
            (uint112 r0, uint112 r1, uint32 _last) = IJoePair(_pair)
                .getReserves();
            if (token0 == _token) {
                swapJoePair(_pair, _token, token1, _getAmtToSwap(r0, _amountIn));
                IJoeRouter(traderJoeRouter).addLiquidity(
                    token0,
                    token1,
                    IERC20(token0).balanceOf(address(this)),
                    IERC20(token1).balanceOf(address(this)),
                    0,
                    0,
                    address(this),
                    block.timestamp
                );
            } else if (token1 == _token) {
                swapJoePair(_pair, _token, token0, _getAmtToSwap(r1, _amountIn));
                IJoeRouter(traderJoeRouter).addLiquidity(
                    token0,
                    token1,
                    IERC20(token0).balanceOf(address(this)),
                    IERC20(token1).balanceOf(address(this)),
                    0,
                    0,
                    address(this),
                    block.timestamp
                );
            } else {
                revert("tokenOut is not a token _in the pair");
            }
            return IERC20(_pair).balanceOf(address(this));
        }
    }


    //////////////////////////////////////////////////////////////////////////////////
    // #3 Swap through Curve 2Pool
    //////////////////////////////////////////////////////////////////////////////////

    // A note on curve swapping:
    // The curve swaps make use of 3 additional helper variables:
    // _misc describes the type of pool interaction. _misc < 0 represents plain pool interactions, _misc > 0 represents
    // interactions with lendingPool and metaPools. abs(_misc) == numCoins in the pool
    // and is used to size arrays when doing add_liquidity
    // _in describes the index of the token being swapped in (if it's -1 it means we're splitting a crvLP token)
    // _out describes the index of the token being swapped out (if it's -1 it means we're trying to mint a crvLP token)
    
    function swapCurve(
        address _tokenIn,
        address _tokenOut,
        address _curvePool,
        uint256 _amount,
        int128 _misc,
        int128 _in,
        int128 _out
    ) internal returns (uint256 amountOut) {
        if (_misc < 0) {
            // Plain pool
            if (_out == -1) {
                _misc = -_misc;
                uint256[] memory _amounts = new uint256[](uint256(int256(_misc)));
                _amounts[uint256(int256(_in))] = _amount;
                if (_misc == 2) {
                    amountOut = IPlainPool(_curvePool).add_liquidity(
                        [_amounts[0], _amounts[1]],
                        0
                    );
                } else if (_misc == 3) {
                    amountOut = IPlainPool(_curvePool).add_liquidity(
                        [_amounts[0], _amounts[1], _amounts[2]],
                        0
                    );
                } else if (_misc == 4) {
                    amountOut = IPlainPool(_curvePool).add_liquidity(
                        [_amounts[0], _amounts[1], _amounts[2], _amounts[3]],
                        0
                    );
                }
            } else if (_in == -1) {
                amountOut = IPlainPool(_curvePool).remove_liquidity_one_coin(
                    _amount,
                    _out,
                    0
                );
            } else {
                amountOut = IPlainPool(_curvePool).exchange(
                    _in,
                    _out,
                    _amount,
                    0
                );
            }
        } else if (_misc > 0) {
            // Use underlying. Works for both lending and metapool
            if (_out == -1) {
                uint256[] memory _amounts = new uint256[](uint256(int256(_misc)));
                _amounts[uint256(int256(_in))] = _amount;
                if (_misc == 2) {
                    amountOut = ILendingPool(_curvePool).add_liquidity(
                        [_amounts[0], _amounts[1]],
                        0,
                        true
                    );
                } else if (_misc == 3) {
                    amountOut = ILendingPool(_curvePool).add_liquidity(
                        [_amounts[0], _amounts[1], _amounts[2]],
                        0,
                        true
                    );
                } else if (_misc == 4) {
                    amountOut = ILendingPool(_curvePool).add_liquidity(
                        [_amounts[0], _amounts[1], _amounts[2], _amounts[3]],
                        0,
                        true
                    );
                }
            } else {
                amountOut = ILendingPool(_curvePool).exchange_underlying(
                    _in,
                    _out,
                    _amount,
                    0
                );
            }
        }
    }

    //////////////////////////////////////////////////////////////////////////////////
    // #4 Convert native to WAVAX
    //////////////////////////////////////////////////////////////////////////////////

    function wrap(bool nativeIn, uint256 _amount) internal returns (uint256) {
        if (nativeIn) {
            WAVAX.deposit{value:_amount}();
        } else {
            WAVAX.withdraw(_amount);
        }
        return _amount;
    }

    //////////////////////////////////////////////////////////////////////////////////
    // #5 Compound-like Token NATIVE not ERC20
    //////////////////////////////////////////////////////////////////////////////////

    function swapCOMPTokenNative(
        address _tokenIn,
        address _cToken,
        uint256 _amount
    ) internal returns (uint256) {
        if (_tokenIn == _cToken) {
            // Swap ctoken for _token
            require(ICOMP(_cToken).redeem(_amount) == 0);
            return address(this).balance;
        } else {
            // Swap _token for ctoken
            ICOMP(_cToken).mint{value:_amount}();
            return IERC20(_cToken).balanceOf(address(this));
        }
    }


    //////////////////////////////////////////////////////////////////////////////////
    // #6 AAVE Token
    //////////////////////////////////////////////////////////////////////////////////

    function swapAAVEToken(
        address _token,
        uint256 _amount,
        bool _AaveIn,
        int128 _misc //Is AAVE V2 or V3?
    ) internal returns (uint256) {
        if (_misc == 3) {
            if (_AaveIn) {
                // Swap Aave for _token
                _amount = IAAVEV3(aaveLendingPoolV3).withdraw(
                    _token,
                    _amount,
                    address(this)
                );
                return _amount;
            } else {
                // Swap _token for Aave
                IAAVEV3(aaveLendingPoolV3).supply(_token, _amount, address(this), 0);
                return _amount;
            }
        } else {
            if (_AaveIn) {
                // Swap Aave for _token
                _amount = IAAVE(aaveLendingPool).withdraw(
                    _token,
                    _amount,
                    address(this)
                );
                return _amount;
            } else {
                // Swap _token for Aave
                IAAVE(aaveLendingPool).deposit(_token, _amount, address(this), 0);
                return _amount;
            }
        }
        
    }

    //////////////////////////////////////////////////////////////////////////////////
    // #7 Compound-like Token
    //////////////////////////////////////////////////////////////////////////////////

    function swapCOMPToken(
        address _tokenIn,
        address _cToken,
        uint256 _amount
    ) internal returns (uint256) {
        if (_tokenIn == _cToken) {
            // Swap ctoken for _token
            require(ICOMP(_cToken).redeem(_amount) == 0);
            address underlying = ICOMP(_cToken).underlying();
            return IERC20(underlying).balanceOf(address(this));
        } else {
            // Swap _token for ctoken
            require(ICOMP(_cToken).mint(_amount) == 0);
            return IERC20(_cToken).balanceOf(address(this));
        }
    }

    //////////////////////////////////////////////////////////////////////////////////
    // #8 Yeti Vault Token
    //////////////////////////////////////////////////////////////////////////////////

    /** 
     * @dev Swaps some protocol token 
     * protocolSwapAddress is the _receiptToken address for that vault token. 
     */ 
    function swapYetiVaultToken(
        address _tokenIn,
        address _receiptToken,
        uint256 _amount
    ) internal returns (uint256) {
        if (_tokenIn == _receiptToken) {
            // Swap _receiptToken for _tokenIn, aka redeem() that amount. 
            return IYetiVaultToken(_receiptToken).redeem(_amount); 
        } else {
            // Swap _tokenIn for _receiptToken, aka deposit() that amount.
            return IYetiVaultToken(_receiptToken).deposit(_amount); 
        }
    }


    //////////////////////////////////////////////////////////////////////////////////
    // #9 Platypus pool
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Swaps through Platypus pool. Routes the same through secondary or main pools. 
     * 
     */
    function swapPlatypus(
        address _tokenIn,
        address _tokenOut,
        address _platypusPool,
        uint256 _amountIn
    ) internal returns (uint256) {
        IPlatypusPool(_platypusPool).swap(
            _tokenIn,
            _tokenOut,
            _amountIn,
            0,
            address(this),
            block.timestamp
        );
    }


    // Takes the address of the token _in, and gives a certain amount of token out. 
    // Calls correct swap functions sequentially based on the route which is defined by the 
    // routes array. 
    function swap(
        address _startingTokenAddress,
        address _endingTokenAddress,
        uint256 _amount,
        uint256 _minSwapAmount
    ) internal returns (uint256) {
        uint256 initialOutAmount = IERC20(_endingTokenAddress).balanceOf(
            address(this)
        );
        Node[] memory path = routes[_startingTokenAddress][_endingTokenAddress];
        uint256 amtIn = _amount;
        require(path.length > 0, "No route found");
        for (uint256 i; i < path.length; i++) {
            if (path[i].nodeType == 1) {
                // Is traderjoe
                _amount = swapJoePair(
                    path[i].protocolSwapAddress,
                    path[i].tokenIn,
                    path[i].tokenOut,
                    _amount
                );
            } else if (path[i].nodeType == 2) {
                // Is jlp
                if (path[i].tokenIn == path[i].protocolSwapAddress) {
                    _amount = swapLPToken(
                        path[i].tokenOut,
                        path[i].protocolSwapAddress,
                        _amount,
                        true
                    );
                } else {
                    _amount = swapLPToken(
                        path[i].tokenIn,
                        path[i].protocolSwapAddress,
                        _amount,
                        false
                    );
                }
            } else if (path[i].nodeType == 3) {
                // Is curve pool
                _amount = swapCurve(
                    path[i].tokenIn,
                    path[i].tokenOut,
                    path[i].protocolSwapAddress,
                    _amount,
                    path[i]._misc,
                    path[i]._in,
                    path[i]._out
                );
            } else if (path[i].nodeType == 4) {
                // Is native<->wrap
                _amount = wrap(
                    path[i].tokenIn == address(1),
                    _amount
                );
            } else if (path[i].nodeType == 5) {
                // Is cToken
                _amount = swapCOMPTokenNative(
                    path[i].tokenIn,
                    path[i].protocolSwapAddress,
                    _amount
                );
            } else if (path[i].nodeType == 6) {
                // Is aToken
                _amount = swapAAVEToken(
                    path[i].tokenIn == path[i].protocolSwapAddress
                        ? path[i].tokenOut
                        : path[i].tokenIn,
                    _amount,
                    path[i].tokenIn == path[i].protocolSwapAddress,
                    path[i]._misc
                );
            } else if (path[i].nodeType == 7) {
                // Is cToken
                _amount = swapCOMPToken(
                    path[i].tokenIn,
                    path[i].protocolSwapAddress,
                    _amount
                );
            } else if (path[i].nodeType == 8) {
                // Is Yeti Vault Token
                _amount = swapYetiVaultToken(
                    path[i].tokenIn,
                    path[i].protocolSwapAddress,
                    _amount
                );
            } else if (path[i].nodeType == 9) {
                // Is Platypus pool 
                _amount = swapPlatypus(
                    path[i].tokenIn,
                    path[i].tokenOut,
                    path[i].protocolSwapAddress,
                    _amount
                );
            } else {
                revert("Unknown node type");
            }
        }
        uint256 outAmount = IERC20(_endingTokenAddress).balanceOf(
            address(this)
        ) - initialOutAmount;
        require(
            outAmount >= _minSwapAmount,
            "Did not receive enough tokens to account for slippage"
        );
        emit Swap(
            msg.sender,
            _startingTokenAddress,
            _endingTokenAddress,
            amtIn,
            _minSwapAmount,
            outAmount
        );
        return outAmount;
    }
}
