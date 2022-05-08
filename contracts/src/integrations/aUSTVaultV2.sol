// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {IxAnchor} from "src/interfaces/IxAnchor.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {ISwapFacility} from "src/interfaces/ISwapFacility.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20Upgradeable} from "solmate/tokens/ERC20Upgradeable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {StringsUpgradeable} from "openzeppelin-contracts-upgradeable/utils/StringsUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC2612} from "src/interfaces/IERC2612.sol";
import {IWAVAX} from "src/interfaces/IWAVAX.sol";

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IWAVAX} from "src/interfaces/IWAVAX.sol";


/** 
 * @notice Vault is an ERC20 implementation which deposits a token to a farm or other contract, 
 * and autocompounds in value for all users. If there has been too much time since the last deliberate
 * reinvestment, the next action will automatically be a reinvestent. This contract is inherited from 
 * the Router contract so it can swap to autocompound. It is inherited by various Vault implementations 
 * to specify how rewards are claimed and how tokens are deposited into different protocols. 
 */

contract aUSTVault is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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

    ///////////////////////////////////////////////////////////////////////////////
    // Modified storage chunk

    IxAnchor public xAnchor;   
    AggregatorV3Interface public priceFeed;
    ISwapFacility public swapper; //Just set to non null value
    ERC20 public UST;

    /* @dev UST balances are rigorously accounted for and adjusted when UST 
    is provided and removed from the system through actual transfers. It is *only* 
    updated to recoincile interest accrual when we are reasonably confident that the aUST
    balance is correct. */
    uint256 public lastUSTBalance;

    /* @dev aUST balances are accounted for by balanceOf() calls and must be treated
    as inherently untrusted because of the time gap between when aUST is made 
    and when it is actually reflected by the bridge transfer */
    uint256 public lastaUSTBalance;

    ///////////////////////////////////////////////////////////////////////////////
    uint256 internal constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function initialize(
        address _underlying, // UST
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _xanchor,
        address _pricefeed,
        address _UST
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        initializeERC20(_name, _symbol, 18);
        underlying = ERC20(_underlying);
        underlyingDecimal = underlying.decimals();
        setFee(_adminFee, _callerFee);
        maxReinvestStale = _maxReinvestStale;
        WAVAX = IWAVAX(_WAVAX);
        
        // Modified chunk
        xAnchor = IxAnchor(_xanchor);
        priceFeed = AggregatorV3Interface(_pricefeed);
        UST = ERC20(_UST);
        UST.approve(_xanchor, MAX_INT);
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

    // DELETED: Reward token functions

    
    function max(uint a, uint b) internal pure returns (uint256) {
        return a < b ? b : a;
    }
    function getTrueUnderlyingBalance() public view returns (uint256) {
        return max(lastaUSTBalance, underlying.balanceOf(address(this)));
    }

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
    
    // How many vault tokens can I get for 1 unit of the underlying * 1e18
    // Can be overriden if underlying balance is not reflected in contract balance
    function receiptPerUnderlying() public view virtual returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        return (1e18 * totalSupply) / getTrueUnderlyingBalance();
    }

    // How many underlying tokens can I get for 1 unit of the vault token * 1e18
    // Can be overriden if underlying balance is not reflected in contract balance
    function underlyingPerReceipt() public view virtual returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** underlyingDecimal;
        }
        return (1e18 * getTrueUnderlyingBalance()) / totalSupply;
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
            UST,
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
            UST,
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

    function _getValueOfUnderlyingPre() internal returns (uint256) {
        return lastUSTBalance;
    }

    /* There is a chance _getValueOfUnderlyingPost() < _getValueOfUnderlyingPre()
        if a large UST deposit is made and compound is called before the aUST arrives
        in the vault. Hence the compound logic is adjusted to account for this  */
    function _getValueOfUnderlyingPost() internal view returns (uint256) {
        return _getUSTaUST() * getTrueUnderlyingBalance() / 1e18;
    }

    function totalHoldings() public view returns (uint256) {
        return getTrueUnderlyingBalance();
    }
    function _preDeposit(uint256 _amt) internal returns (uint256) {
        return 1e18 * _amt / _getUSTaUST();
    }
    
    function _triggerDepositAction(uint256 amtOfUnderlying) internal  {
        uint256 rate = _getUSTaUST();
        lastaUSTBalance = getTrueUnderlyingBalance() + (amtOfUnderlying * 1e18 / rate );
        /* One of two places where UST interest accrual is updated. Ensures monotonic increases 
        in case newly deposited aUST has not landed yet */
        lastUSTBalance = rate * lastaUSTBalance / 1e18;
        xAnchor.depositStable(address(UST), amtOfUnderlying);
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal {
        lastaUSTBalance = getTrueUnderlyingBalance() - amtToReturn;
        lastUSTBalance -= 1e18 * amtToReturn / _getUSTaUST();
    }
    

    function _compound() internal returns (uint256) {
        uint256 preCompoundUnderlyingValue = _getValueOfUnderlyingPre();
        uint256 postCompoundUnderlyingValue = _getValueOfUnderlyingPost();
        /* @dev Removed profit calculation because postCompoundUnderlyingValue 
        can be < preCompoundUnderlyingValue as mentioned above. */
        if (postCompoundUnderlyingValue > preCompoundUnderlyingValue) {
            /* We only consider a successful compound if there is a profit. 
            Otherwise it will attempt again when aUST has landed in the vault */
            lastReinvestTime = block.timestamp;

            uint256 profitInUnderlying = postCompoundUnderlyingValue - preCompoundUnderlyingValue;
            uint256 adminAmt = (profitInUnderlying * adminFee) / 10000;
            uint256 callerAmt = (profitInUnderlying * callerFee) / 10000;
            _triggerWithdrawAction(adminAmt + callerAmt);
            SafeTransferLib.safeTransfer(underlying, feeRecipient, adminAmt);
            SafeTransferLib.safeTransfer(underlying, msg.sender, callerAmt);
            emit Reinvested(
                msg.sender,
                preCompoundUnderlyingValue,
                postCompoundUnderlyingValue
            );
            emit AdminFeePaid(feeRecipient, adminAmt);
            emit CallerFeePaid(msg.sender, callerAmt);
            lastaUSTBalance = getTrueUnderlyingBalance();
            lastUSTBalance = _getUSTaUST() * lastaUSTBalance / 1e18;
        }
     }


    // Emergency withdraw in case of previously failed operations
    // Notice that this address is the Terra address of the token
    function emergencyWithdraw(string calldata token) public onlyOwner {
        xAnchor.withdrawAsset(token);
    }

    // If something weird happens. Recoincile balances.
    function forceBalanceUpdate() external onlyOwner {
        lastaUSTBalance = underlying.balanceOf(address(this));
        lastUSTBalance = _getUSTaUST() * underlying.balanceOf(address(this)) / 1e18;
    }

    function compound() external nonReentrant returns (uint256) {
        return _compound();
    }

    fallback() external payable {
        return;
    }

   
}