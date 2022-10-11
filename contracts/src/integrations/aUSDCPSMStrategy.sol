// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {IYetiVaultToken} from "../interfaces/IYetiVaultToken.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAAVEV3} from "../interfaces/IAAVE.sol";

/**
 * Handles the deposit and withdraw functionality in the Aave USDC strategy for the PSM.
 */

contract aUSDCPSMStrategy is IStrategy, Ownable {

    uint256 internal constant MAX_UINT = type(uint).max;

    IERC20 public constant USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IYetiVaultToken public constant vaultStrategy = IYetiVaultToken(0xAD69de0CE8aB50B729d3f798d7bC9ac7b4e79267);
    IERC20 public constant underlying = IERC20(0x625E7708f30cA75bfd92586e17077590C60eb4cD);
    address public constant aaveLendingPoolV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    address public immutable PSM;

    constructor(address _psm) public {
        transferOwnership(_psm);
        PSM = _psm;
        // Approve aave lending pool to convert USDC to aUSDC
        USDC.approve(address(aaveLendingPoolV3), MAX_UINT);
        // Approve strategy (YaV3USDC strategy) to convert aUSDC to yeti vault aUSDC
        underlying.approve(address(vaultStrategy), MAX_UINT);
    }

    /// Deposit USDC into the strategy from the PSM
    function deposit(uint256 _depositAmount) external override onlyOwner returns (uint256) {
        if(_depositAmount != 0) {
            USDC.transferFrom(PSM, address(this), _depositAmount);
            uint256 resultingAmount = swapAAVEToken(_depositAmount, false);
            uint256 actualAmountToDeposit = _min(resultingAmount, underlying.balanceOf(address(this)));
            return vaultStrategy.deposit(actualAmountToDeposit);
        }
    }

    /// Withdraw USDC from the strategy from the PSM
    function withdraw(uint256 _withdrawAmountInUSDC) external override onlyOwner returns (uint256) {
        if (_withdrawAmountInUSDC != 0) {
            uint256 withdrawAmountInVault = _withdrawAmountInUSDC * (vaultStrategy.receiptPerUnderlying()) / (1e18);
            uint256 amount_vault_aUSDC = _min(withdrawAmountInVault, IERC20(address(vaultStrategy)).balanceOf(address(this)));
            uint256 resultingAmountInUSDC = vaultStrategy.withdraw(amount_vault_aUSDC);
            uint256 amount_aUSDC = _min(resultingAmountInUSDC, underlying.balanceOf(address(this)));
            uint256 resultingAmountInUSDC2 = swapAAVEToken(amount_aUSDC, true);
            uint256 amountUSDCToTransferFinal = _min(resultingAmountInUSDC2, USDC.balanceOf(address(this)));
            USDC.transfer(PSM, amountUSDCToTransferFinal);
            return amountUSDCToTransferFinal;
        }
    }

    /// Total amount of USDC the contract owns. 
    function totalHoldings() external view override returns (uint256 USDCBalance) {
        uint256 balance = IERC20(address(vaultStrategy)).balanceOf(address(this));
        uint256 underlyingPerReceipt = vaultStrategy.underlyingPerReceipt();
        USDCBalance = balance * (underlyingPerReceipt) / (1e18);
    }

    // Deposits or withdraws from aUSDC token
    function swapAAVEToken(
        uint256 _amount,
        bool _AaveIn
    ) internal returns (uint256) {
        if (_AaveIn) {
                // Swap Aave for _token
                _amount = IAAVEV3(aaveLendingPoolV3).withdraw(
                    address(USDC),
                    _amount,
                    address(this)
                );
                return _amount;
            } else {
                // Swap _token for Aave
                IAAVEV3(aaveLendingPoolV3).supply(address(USDC), _amount, address(this), 0);
                return _amount;
            }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
