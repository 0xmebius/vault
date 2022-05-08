// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./Router.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/** 
 * @notice Lever is a contract intended for use in the Yeti Finance Lever Up feature. It routes from 
 * YUSD to some various token out which has to be compatible with the underlying router in the route 
 * function, and unRoutes backwards to get YUSD out. Sends to the active pool address by intention and 
 * route is called in functions openTroveLeverUp and addCollLeverUp in BorrowerOperations.sol. unRoute
 * is called in functions closeTroveUnleverUp and withdrawCollUnleverUp in BorrowerOperations.sol.
 */

contract Lever is Router, ReentrancyGuard {
    constructor() {
        initialize();
    }
    function initialize() public initializer {
        __Ownable_init();
    }

    // Goes from some token (YUSD likely) and gives a certain amount of token out.
    // Auto transfers to active pool from call in BorrowerOperations.sol, aka _toUser is always activePool
    // Goes from _startingTokenAddress to _endingTokenAddress, pulling tokens from _fromUser, of _amount, and gets _minSwapAmount out _endingTokenAddress
    function route(
        address _toUser,
        address _startingTokenAddress,
        address _endingTokenAddress,
        uint256 _amount,
        uint256 _minSwapAmount
    ) external nonReentrant returns (uint256 amountOut) {
        amountOut = swap(
            _startingTokenAddress,
            _endingTokenAddress,
            _amount,
            _minSwapAmount
        );
        SafeTransferLib.safeTransfer(ERC20(_endingTokenAddress), _toUser, amountOut);
    }

    // Takes the address of the token required in, and gives a certain amount of any token (YUSD likely) out
    // User first withdraws that collateral from the active pool, then performs this swap. Unwraps tokens
    // for the user in that case.
    // Goes from _startingTokenAddress to _endingTokenAddress, pulling tokens from _fromUser, of _amount, and gets _minSwapAmount out _endingTokenAddress.
    // Use case: Takes token from trove debt which has been transfered to the owner and then swaps it for YUSD, intended to repay debt.
    function unRoute(
        address _toUser,
        address _startingTokenAddress,
        address _endingTokenAddress,
        uint256 _amount,
        uint256 _minSwapAmount
    ) external nonReentrant returns (uint256 amountOut) {
        amountOut = swap(
            _startingTokenAddress,
            _endingTokenAddress,
            _amount,
            _minSwapAmount
        );
        SafeTransferLib.safeTransfer(ERC20(_endingTokenAddress), _toUser, amountOut);
    }

    function fullTx(
        address _startingTokenAddress,
        address _endingTokenAddress,
        uint256 _amount,
        uint256 _minSwapAmount
    ) external nonReentrant returns (uint256 amountOut) {
        SafeTransferLib.safeTransferFrom(ERC20(_startingTokenAddress), msg.sender, address(this), _amount);
        amountOut = swap(
            _startingTokenAddress,
            _endingTokenAddress,
            _amount,
            _minSwapAmount
        );
        SafeTransferLib.safeTransfer(ERC20(_endingTokenAddress), msg.sender, amountOut);
    }

    fallback() external payable {
        return;
    }
}
