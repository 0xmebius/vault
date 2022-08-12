// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import {IPSM} from "./interfaces/IPSM.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IBurner} from "./interfaces/IBurner.sol";
import {IYUSDToken} from "./interfaces/IYUSDToken.sol";

// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&@@@@@@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&   ,.@@@@@@@@@@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@@@&&&.,,      ,,**.&&&&&@@@@@@@@@@@@@@
// @@@@@@@@@@@@@@@@@@@@@@,               ..,,,,,,,,,&@@@@@@@@@@
// @@@@@@,,,,,,&@@@@@@@@&                       ,,,,,&@@@@@@@@@
// @@@&,,,,,,,,@@@@@@@@@                        ,,,,,*@@@/@@@@@
// @@,*,*,*,*#,,*,&@@@@@   $$          $$       *,,,  ***&@@@@@
// @&***********(@@@@@@&   $$          $$       ,,,%&. & %@@@@@
// @(*****&**     &@@@@#                        *,,%  ,#%@*&@@@
// @... &             &                         **,,*&,(@*,*,&@
// @&,,.              &                         *,*       **,,@
// @@@,,,.            *                         **         ,*,,
// @@@@@,,,...   .,,,,&                        .,%          *,*
// @@@@@@@&/,,,,,,,,,,,,&,,,,,.         .,,,,,,,,.           *,
// @@@@@@@@@@@@&&@(,,,,,(@&&@@&&&&&%&&&&&%%%&,,,&            .(
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&,,,,,,,,,,,,,,&             &
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@/,,,,,,,,,,,,&             &
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@/            &             &
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&              &             &
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&      ,,,@@@&  &  &&  .&( &#%
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&&&&%#**@@@&*&*******,,,,,**
//
//  $$\     $$\          $$\     $$\       $$$$$$$$\ $$\                                                   
//  \$$\   $$  |         $$ |    \__|      $$  _____|\__|                                                  
//   \$$\ $$  /$$$$$$\ $$$$$$\   $$\       $$ |      $$\ $$$$$$$\   $$$$$$\  $$$$$$$\   $$$$$$$\  $$$$$$\  
//    \$$$$  /$$  __$$\\_$$  _|  $$ |      $$$$$\    $$ |$$  __$$\  \____$$\ $$  __$$\ $$  _____|$$  __$$\ 
//     \$$  / $$$$$$$$ | $$ |    $$ |      $$  __|   $$ |$$ |  $$ | $$$$$$$ |$$ |  $$ |$$ /      $$$$$$$$ |
//      $$ |  $$   ____| $$ |$$\ $$ |      $$ |      $$ |$$ |  $$ |$$  __$$ |$$ |  $$ |$$ |      $$   ____|
//      $$ |  \$$$$$$$\  \$$$$  |$$ |      $$ |      $$ |$$ |  $$ |\$$$$$$$ |$$ |  $$ |\$$$$$$$\ \$$$$$$$\ 
//      \__|   \_______|  \____/ \__|      \__|      \__|\__|  \__| \_______|\__|  \__| \_______| \_______|

/** 
 * @notice PSM is a contract meant for swapping USDC for YUSD after taking a small fee. It will deposit
 * the USDC it receives into some Strategy contract, such as depositing in Aave to get aUSDC, to compound
 * the amount of USDC that it has available to swap back to YUSD, if YUSD ever drifts under peg. The strategy
 * contract will hold the USDC or some derivative of USDC, and it will be retrievable if necessary. When transitioning
 * to a new strategy, the old strategy will have its privileges revoked and the new strategy will be executed. 
 * 
 * Using the PSM to swap USDC to mint YUSD will be profitable if YUSD is over peg. It will be profitable to redeem YUSD for USDC
 * in the case that YUSD is trading below $1. The PSM is intended to be used before redemptions happen in the main protocol. 
 *
 * There will be a max on the PSM and a controller/owner which can update parameters such as max YUSD minted,
 * strategy used, fee, etc. The owner will be upgraded to a timelocked contract after a certain launch period.
 * 
 */

contract PSM is ReentrancyGuardUpgradeable, OwnableUpgradeable, IPSM {
    using SafeTransferLib for IERC20;

    /// ===========================================
    /// State variables, events, and initializer
    /// ===========================================

    uint256 internal constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    ERC20 public constant USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    ERC20 public constant YUSDERC20 = ERC20(0x111111111111ed1D73f860F57b2798b683f2d325);
    IYUSDToken public constant YUSDToken = IYUSDToken(0x111111111111ed1D73f860F57b2798b683f2d325);

    /// Conversion between USDC and YUSD, since USDC is 6 decimals, and YUSD is 18.
    uint256 private constant DECIMAL_CONVERSION = 1e12;

    /// Contract through which to burn YUSD
    IBurner public burner;

    /// Receives fees from mint/redeem and from harvesting
    address public feeRecipient;

    /// Strategy that deposits the USDC to earn additional yield or put it to use. 
    IStrategy public strategy;

    /// Max amount of YUSD this contract can hold as debt
    /// To pause minting, set debt limit to 0. 
    uint256 public YUSDDebtLimit;

    /// Whether or not redeeming YUSD is paused
    bool public redeemPaused;

    /// Current YUSD Debt this contract holds
    uint256 public YUSDContractDebt;

    /// Fee for each swap of YUSD and USDC, through mintYUSD or redeemYUSD functions. In basis points (out of 10000).
    uint256 public swapFee; 

    /// 1 - swapFee, so the amount of YUSD or USDC you get in return for swapping. 
    uint256 public swapFeeCompliment;

    /// basis points
    uint256 private constant SWAP_FEE_DENOMINATOR = 10000;

    event YUSDMinted(uint256 YUSDAmount, address minter, address recipient);

    event YUSDRedeemed(uint256 YUSDAmount, address burner, address recipient);

    event YUSDContractDebtChanged(uint256 newYUSDContractDebt);

    event YUSDHarvested(uint256 YUSDAmount);

    event NewFeeSet(uint256 _newSwapFee);

    event NewDebtLimitSet(uint256 _newDebtLimit);
    
    event RedeemPauseToggle(bool _paused);

    event NewFeeRecipientSet(address _newFeeRecipient);

    event NewStrategySet(address _newStrategy);

    /**
     * @notice initializer function, sets all relevant parameters.
     */
    function initialize(address _burner, address _strategy, address _feeRecipient, uint256 _limit, uint256 _swapFee) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        require(_burner != address(0), "Nonzero burner");
        burner = IBurner(_burner);

        require(OwnableUpgradeable(_strategy).owner() == address(this), "Not initialized or wrong owner of strategy");
        USDC.approve(_strategy, MAX_UINT);
        strategy = IStrategy(_strategy);
        emit NewStrategySet(_strategy);

        require(_feeRecipient != address(0), "Nonzero address recipient");
        feeRecipient = _feeRecipient;
        emit NewFeeRecipientSet(_feeRecipient);

        YUSDDebtLimit = _limit;
        emit NewDebtLimitSet(_limit);

        require(_swapFee <= SWAP_FEE_DENOMINATOR, "Swap fee invalid");
        swapFee = _swapFee;
        swapFeeCompliment = SWAP_FEE_DENOMINATOR - _swapFee;
        emit NewFeeSet(_swapFee);

        emit RedeemPauseToggle(false);
    }

    /// ===========================================
    /// External use functions
    /// ===========================================

    /** 
     * @notice Send USDC to receive YUSD in return, at a 1 to 1 ratio minus the fee. Will increase debt of the contract by 
     * that amount, if possible (lower than cap). Deposits into the strategy. 
     * @param _USDCAmount The amount of USDC the user would like to mint YUSD with. Will be in terms of 10**6 decimals
     * @param _recipient Intended recipient for YUSD minted
     * @return YUSDAmount The amount of YUSD the recipient receives back after the fee. Will be in terms of 10**18 decimals
     */
    function mintYUSD(uint256 _USDCAmount, address _recipient) external override nonReentrant returns (uint256 YUSDAmount) {
        require(_USDCAmount > 0, "0 mint not allowed");

        // Pull in USDC from user
        SafeTransferLib.safeTransferFrom(
            USDC,
            msg.sender,
            address(this),
            _USDCAmount
        );

        // Amount of YUSD that will be minted, and amount of USDC actually given to this contract
        uint256 USDCAmountToDeposit = _USDCAmount * swapFeeCompliment / SWAP_FEE_DENOMINATOR;
        YUSDAmount = USDCAmountToDeposit * DECIMAL_CONVERSION;
        require(YUSDAmount + YUSDContractDebt < YUSDDebtLimit, "Cannot mint more than PSM Debt limit");

        // Send fee to recipient, in USDC
        uint256 USDCFeeAmount = _USDCAmount * swapFee / SWAP_FEE_DENOMINATOR;
        SafeTransferLib.safeTransfer(
            USDC, 
            feeRecipient,
            USDCFeeAmount
        );

        // Deposit into strategy
        strategy.deposit(USDCAmountToDeposit);

        // Mint recipient YUSD
        YUSDToken.mint(_recipient, YUSDAmount);

        // Update contract debt
        YUSDContractDebt = YUSDContractDebt + YUSDAmount;

        emit YUSDMinted(YUSDAmount, msg.sender, _recipient);
        emit YUSDContractDebtChanged(YUSDContractDebt);
    }

    /** 
     * @notice Send YUSD to receive USDC in return, at a 1 to 1 ratio minus the fee. Will decrease debt of the contract by 
     * that amount, if possible (if less than 0 then just reduce to 0). Burns the YUSD.
     * Receives the correct amount of USDC from the Strategy when it is redeemed. 
     * @param _YUSDAmount The amount of YUSD the user would like to redeem for USDC. Will be in terms of 10**18 decimals
     * @param _recipient Intended recipient for USDC returned
     * @return USDCAmount The amount of USDC the recipient receives back after the fee. Will be in terms of 10**6 decimals
     */
    function redeemYUSD(uint256 _YUSDAmount, address _recipient) external override nonReentrant returns (uint256 USDCAmount) {
        require(!redeemPaused, "Redeem paused");
        require(_YUSDAmount > 0, "0 redeem not allowed");

        // Pull in YUSD from user
        SafeTransferLib.safeTransferFrom(
            YUSDERC20,
            msg.sender,
            address(this),
            _YUSDAmount
        );

        // Amount of USDC that will be returned, and amount of YUSD burned
        // Amount of YUSD burned
        uint256 YUSDBurned = _YUSDAmount * swapFeeCompliment / SWAP_FEE_DENOMINATOR;
        USDCAmount = YUSDBurned / DECIMAL_CONVERSION;
        require(YUSDBurned < YUSDContractDebt, "Burning more than the contract has in debt");

        // Burn the YUSD
        burner.burn(address(this), YUSDBurned);

        // Send fee to recipient, in YUSD
        uint256 YUSDFeeAmount = _YUSDAmount * swapFee / SWAP_FEE_DENOMINATOR;
        SafeTransferLib.safeTransfer(
            YUSDERC20,
            feeRecipient,
            YUSDFeeAmount
        );

        // Withdraw from strategy
        strategy.withdraw(USDCAmount);

        // Send back USDC
        SafeTransferLib.safeTransfer(
            USDC, 
            _recipient,
            USDCAmount
        );

        // Update contract debt
        YUSDContractDebt = YUSDContractDebt - YUSDBurned;

        emit YUSDRedeemed(YUSDBurned, msg.sender, _recipient);
        emit YUSDContractDebtChanged(YUSDContractDebt);
    }

    /// ===========================================
    /// Admin parameter functions
    /// ===========================================

    /** 
     * @notice Sets new swap fee
     */
    function setFee(uint256 _newSwapFee) external override onlyOwner {
        require(_newSwapFee <= SWAP_FEE_DENOMINATOR, "Swap fee invalid");
        swapFee = _newSwapFee;
        swapFeeCompliment = SWAP_FEE_DENOMINATOR - _newSwapFee;
        emit NewFeeSet(_newSwapFee);
    }

    /** 
     * @notice Sets new YUSD Debt limit
     *  Can be set to 0 to stop any new minting
     */
    function setDebtLimit(uint256 _newDebtLimit) external override onlyOwner {
        YUSDDebtLimit = _newDebtLimit;
        emit NewDebtLimitSet(_newDebtLimit);
    }

    /**
     * @notice Sets whether redeeming is allowed or not
     */
    function toggleRedeemPaused(bool _paused) external override onlyOwner {
        redeemPaused = _paused;
        emit RedeemPauseToggle(_paused);
    }

    /**
     * @notice Sets fee recipient which will get a certain swapFee per swap
     */
    function setFeeRecipient(address _newFeeRecipient) external override onlyOwner {
        require(_newFeeRecipient != address(0), "Nonzero address recipient");
        feeRecipient = _newFeeRecipient;
        emit NewFeeRecipientSet(_newFeeRecipient);
    }

    /** 
     * @notice Sets new strategy for USDC utilization
     */
    function setStrategy(address _newStrategy) external override onlyOwner {
        require(OwnableUpgradeable(_newStrategy).owner() == address(this), "Not initialized or wrong owner of strategy");

        // Withdraw from old strategy
        uint256 totalHoldings = strategy.totalHoldings();
        strategy.withdraw(totalHoldings);
        USDC.approve(address(strategy), 0);

        // Deposit into new strategy after approving USDC
        USDC.approve(_newStrategy, MAX_UINT);
        strategy = IStrategy(_newStrategy);
        strategy.deposit(totalHoldings);

        emit NewStrategySet(_newStrategy);
    }

    /** 
     * @notice Aligns tracked debt with USDC value. Mints surplus to fee recipient to match YUSD
     * and USDC holdings
     * @return harvestAmount : The amount in YUSD that is minted to the fee recipient based on the discrepancy
     */
    function harvest() external returns (uint256 harvestAmount) {
        // Total holdings of yield contract, in 1e18 (YUSD)
        uint256 totalHoldings = strategy.totalHoldings() * DECIMAL_CONVERSION;
        require(totalHoldings > YUSDContractDebt, "Can't send negative or 0 YUSD");
        require(totalHoldings <= YUSDDebtLimit, "Cannot mint more than PSM Debt limit");

        // Mint YUSD to fee recipient
        harvestAmount = totalHoldings - YUSDContractDebt;
        YUSDToken.mint(feeRecipient, harvestAmount);

        // Align values
        YUSDContractDebt = totalHoldings;

        emit YUSDHarvested(harvestAmount);
        emit YUSDContractDebtChanged(YUSDContractDebt);
    }
}

