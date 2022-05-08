// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20Upgradeable} from "solmate/tokens/ERC20Upgradeable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {StringsUpgradeable} from "openzeppelin-contracts-upgradeable/utils/StringsUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC2612} from "./interfaces/IERC2612.sol";
import {IWAVAX} from "./interfaces/IWAVAX.sol";

import "./Router.sol";

/** 
 * @notice Vault is an ERC20 implementation which deposits a token to a farm or other contract, 
 * and autocompounds in value for all users. If there has been too much time since the last deliberate
 * reinvestment, the next action will automatically be a reinvestent. This contract is inherited from 
 * the Router contract so it can swap to autocompound. It is inherited by various Vault implementations 
 * to specify how rewards are claimed and how tokens are deposited into different protocols. 
 */

contract Vault is ERC20Upgradeable, Router, ReentrancyGuardUpgradeable {
    using SafeTransferLib for IERC20;

    // Min swap to rid of edge cases with untracked rewards for small deposits. 
    uint256 constant public MIN_SWAP = 1e16;
    uint256 constant public MIN_FIRST_MINT = 1e12; // Require substantial first mint to prevent exploits from rounding errors
    uint256 constant public FIRST_DONATION = 1e8; // Lock in first donation to prevent exploits from rounding errors

    uint256 public underlyingDecimal; //decimal of underlying token
    ERC20 public underlying; // the underlying token

    address[] public rewardTokens; //List of reward tokens send to this vault. address(1) indicates raw AVAX
    uint256 public lastReinvestTime; // Timestamp of last reinvestment
    uint256 public maxReinvestStale; //Max amount of time in seconds between a reinvest
    address public feeRecipient; //Owner of admin fee
    uint256 public adminFee; // Fee in bps paid out to admin on each reinvest
    uint256 public callerFee; // Fee in bps paid out to caller on each reinvest
    address public BOpsAddress;
    IWAVAX public WAVAX;

    event Reinvested(address caller, uint256 preCompound, uint256 postCompound);
    event CallerFeePaid(address caller, uint256 amount);
    event AdminFeePaid(address caller, uint256 amount);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event RewardTokenSet(address caller, uint256 index, address rewardToken);
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;


    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX
        ) public virtual initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        initializeERC20(_name, _symbol, 18);
        underlying = ERC20(_underlying);
        underlyingDecimal = underlying.decimals();
        setFee(_adminFee, _callerFee);
        maxReinvestStale = _maxReinvestStale;
        WAVAX = IWAVAX(_WAVAX);
    }
    
    // Sets fee
    function setFee(uint256 _adminFee, uint256 _callerFee) public onlyOwner {
        require(_adminFee < 10000 && _callerFee < 10000);
        adminFee = _adminFee;
        callerFee = _callerFee;
    }

    // Sets the maxReinvest stale
    function setStale(uint256 _maxReinvestStale) public onlyOwner {
        maxReinvestStale = _maxReinvestStale;
    }

    // Sets the address of the BorrowerOperations contract which will have permissions to depositFor. 
    function setBOps(address _BOpsAddress) public onlyOwner {
        BOpsAddress = _BOpsAddress;
    }

    // Sets fee recipient which will get a certain adminFee percentage of reinvestments. 
    function setFeeRecipient(address _feeRecipient) public onlyOwner {
        feeRecipient = _feeRecipient;
    }

    // Add reward token to list of reward tokens
    function pushRewardToken(address _token) public onlyOwner {
        require(address(_token) != address(0), "0 address");
        rewardTokens.push(_token);
    }

    // If for some reason a reward token needs to be deprecated it is set to 0
    function deprecateRewardToken(uint256 _index) public onlyOwner {
        require(_index < rewardTokens.length, "Out of bounds");
        rewardTokens[_index] = address(0);
    }

    function numRewardTokens() public view returns (uint256) {
        return rewardTokens.length;
    }

    function getRewardToken(uint256 _ind) public view returns (address) {
        return rewardTokens[_ind];
    }

    // How many vault tokens can I get for 1 unit of the underlying * 1e18
    // Can be overriden if underlying balance is not reflected in contract balance
    function receiptPerUnderlying() public view virtual returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        return (1e18 * totalSupply) / underlying.balanceOf(address(this));
    }

    // How many underlying tokens can I get for 1 unit of the vault token * 1e18
    // Can be overriden if underlying balance is not reflected in contract balance
    function underlyingPerReceipt() public view virtual returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** underlyingDecimal;
        }
        return (1e18 * underlying.balanceOf(address(this))) / totalSupply;
    }

    // Deposit underlying for a given amount of vault tokens. Buys in at the current receipt
    // per underlying and then transfers it to the original sender. 
    function deposit(address _to, uint256 _amt) public nonReentrant returns (uint256 receiptTokens) {
        require(_amt > 0, "0 tokens");
        // Reinvest if it has been a while since last reinvest
        if (block.timestamp > lastReinvestTime + maxReinvestStale) {
            _compound();
        }
        uint256 _toMint = _preDeposit(_amt);
        receiptTokens = (receiptPerUnderlying() * _toMint) / 1e18;
        if (totalSupply == 0) {
            require(receiptTokens >= MIN_FIRST_MINT);
            _mint(feeRecipient, FIRST_DONATION);
            receiptTokens -= FIRST_DONATION;
        }
        require(
            receiptTokens != 0,
            "0 received"
        );
        SafeTransferLib.safeTransferFrom(
            underlying,
            msg.sender,
            address(this),
            _amt
        );
        _triggerDepositAction(_amt);
        _mint(_to, receiptTokens);
        emit Deposit(msg.sender, _to, _amt, receiptTokens);
    }
    
    function deposit(uint256 _amt) public returns (uint256) {
        return deposit(msg.sender, _amt);
    }

    // For use in the YETI borrowing protocol, depositFor assumes approval of the underlying token to the router, 
    // and it is only callable from the BOps contract. 
    function depositFor(address _borrower, address _to, uint256 _amt) public nonReentrant returns (uint256 receiptTokens) {
        require(msg.sender == BOpsAddress, "BOps only");
        require(_amt > 0, "0 tokens");
        // Reinvest if it has been a while since last reinvest
        if (block.timestamp > lastReinvestTime + maxReinvestStale) {
            _compound();
        }
        uint256 _toMint = _preDeposit(_amt);
        receiptTokens = (receiptPerUnderlying() * _toMint) / 1e18;
        require(
            receiptTokens != 0,
            "Deposit amount too small, you will get 0 receipt tokens"
        );
        SafeTransferLib.safeTransferFrom(
            underlying,
            _borrower,
            address(this),
            _amt
        );
        _triggerDepositAction(_amt);
        _mint(_to, receiptTokens);
        emit Deposit(_borrower, _to, _amt, receiptTokens);
    }

    // Deposit underlying token supporting gasless approvals
    function depositWithPermit(
        uint256 _amt,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public returns (uint256 receiptTokens) {
        IERC2612(address(underlying)).permit(
            msg.sender,
            address(this),
            _value,
            _deadline,
            _v,
            _r,
            _s
        );
        return deposit(_amt);
    }

    // Withdraw underlying tokens for a given amount of vault tokens
    function redeem(address _to, uint256 _amt) public virtual nonReentrant returns (uint256 amtToReturn) {
        // require(_amt > 0, "0 tokens");
        if (block.timestamp > lastReinvestTime + maxReinvestStale) {
            _compound();
        }
        amtToReturn = (underlyingPerReceipt() * _amt) / 1e18;
        _triggerWithdrawAction(amtToReturn);
        _burn(msg.sender, _amt);
        SafeTransferLib.safeTransfer(underlying, _to, amtToReturn);
        emit Withdraw(msg.sender, _to, msg.sender, amtToReturn, _amt);
    }

    function redeem(uint256 _amt) public returns (uint256) {
        return redeem(msg.sender, _amt);
    }

    // Bailout in case compound() breaks
    function emergencyRedeem(uint256 _amt)
        public nonReentrant
        returns (uint256 amtToReturn)
    {
        amtToReturn = (underlyingPerReceipt() * _amt) / 1e18;
        _triggerWithdrawAction(amtToReturn);
        _burn(msg.sender, _amt);
        SafeTransferLib.safeTransfer(underlying, msg.sender, amtToReturn);
        emit Withdraw(msg.sender, msg.sender, msg.sender, amtToReturn, _amt);
    }

    // Withdraw receipt tokens from another user with approval
    function redeemFor(
        uint256 _amt,
        address _from,
        address _to
    ) public nonReentrant returns (uint256 amtToReturn) {
        // require(_amt > 0, "0 tokens");
        if (block.timestamp > lastReinvestTime + maxReinvestStale) {
            _compound();
        }

        uint256 allowed = allowance[_from][msg.sender];
        // Below line should throw if allowance is not enough, or if from is the caller itself. 
        if (allowed != type(uint256).max && msg.sender != _from) {
            allowance[_from][msg.sender] = allowed - _amt;
        }
        amtToReturn = (underlyingPerReceipt() * _amt) / 1e18;
        _triggerWithdrawAction(amtToReturn);
        _burn(_from, _amt);
        SafeTransferLib.safeTransfer(underlying, _to, amtToReturn);
        emit Withdraw(msg.sender, _to, _from, amtToReturn, _amt);
    }

    // Temporary function to allow current testnet deployment
    function withdrawFor(
        uint256 _amt,
        address _from,
        address _to
    ) external returns (uint256) {
        return redeemFor(_amt, _from, _to);
    }
    function withdraw(
        uint256 _amt
    ) external returns (uint256) {
        return redeem(msg.sender, _amt);
    }

    // Withdraw receipt tokens from another user with gasless approval
    function redeemForWithPermit(
        uint256 _amt,
        address _from,
        address _to,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public returns (uint256) {
        permit(_from, msg.sender, _value, _deadline, _v, _r, _s);
        return redeemFor(_amt, _from, _to);
    }

    function totalHoldings() public virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    // Once underlying has been deposited tokens may need to be invested in a staking thing
    function _triggerDepositAction(uint256 _amt) internal virtual {
        return;
    }

    // If a user needs to withdraw underlying, we may need to unstake from something
    function _triggerWithdrawAction(uint256 amtToReturn)
        internal
        virtual
    {
        return;
    }

    // Function that will pull rewards into the contract
    // Will be overridenn by child classes
    function _pullRewards() internal virtual {
        return;
    }

    function _preDeposit(uint256 _amt) internal virtual returns (uint256) {
        return _amt;
    }

    // Function that calculates value of underlying tokens, by default it just does it
    // based on balance. 
    // Will be overridenn by child classes
    function _getValueOfUnderlyingPre() internal virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function _getValueOfUnderlyingPost() internal virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function compound() external nonReentrant returns (uint256) {
        return _compound();
    }

    function _doSomethingPostCompound() internal virtual {
        return;
    }

    fallback() external payable {
        return;
    }

    // Compounding function
    // Loops through all reward tokens and swaps for underlying using inherited router
    // Pays fee to caller to incentivize compounding
    // Pays fee to admin
    function _compound() internal virtual returns (uint256) {
        address _underlyingAddress = address(underlying);
        lastReinvestTime = block.timestamp;
        uint256 preCompoundUnderlyingValue = _getValueOfUnderlyingPre();
        _pullRewards();
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] != address(0)) {
                if (rewardTokens[i] == _underlyingAddress) continue;
                if (rewardTokens[i] == address(1)) {
                    // Token is native currency
                    // Deposit for WAVAX
                    uint256 nativeBalance = address(this).balance;
                    if (nativeBalance > MIN_SWAP) {
                        WAVAX.deposit{value: nativeBalance}();
                        swap(
                            address(WAVAX),
                            _underlyingAddress,
                            nativeBalance,
                            0
                        );
                    }
                } else {
                    uint256 rewardBalance = IERC20(rewardTokens[i]).balanceOf(
                        address(this)
                    );
                    if (rewardBalance * (10 ** (18 - IERC20(rewardTokens[i]).decimals())) > MIN_SWAP ) {
                        swap(
                            rewardTokens[i],
                            _underlyingAddress,
                            rewardBalance,
                            0
                        );
                    }
                }
            }
        }
        uint256 postCompoundUnderlyingValue = _getValueOfUnderlyingPost();
        uint256 profitInValue = postCompoundUnderlyingValue - preCompoundUnderlyingValue;
        if (profitInValue > 0) {
            // convert the profit in value to profit in underlying
            uint256 profitInUnderlying = profitInValue * underlying.balanceOf(address(this)) / postCompoundUnderlyingValue;
            uint256 adminAmt = (profitInUnderlying * adminFee) / 10000;
            uint256 callerAmt = (profitInUnderlying * callerFee) / 10000;

            SafeTransferLib.safeTransfer(underlying, feeRecipient, adminAmt);
            SafeTransferLib.safeTransfer(underlying, msg.sender, callerAmt);
            emit Reinvested(
                msg.sender,
                preCompoundUnderlyingValue,
                postCompoundUnderlyingValue
            );
            emit AdminFeePaid(feeRecipient, adminAmt);
            emit CallerFeePaid(msg.sender, callerAmt);
            // For tokens which have to deposit their newly minted tokens to deposit them into another contract,
            // call that action. New tokens = current balance of underlying. 
            _triggerDepositAction(underlying.balanceOf(address(this)));
        }
        _doSomethingPostCompound();
    }
}
