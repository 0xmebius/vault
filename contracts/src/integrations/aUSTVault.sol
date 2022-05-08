// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";
import {IxAnchor} from "src/interfaces/IxAnchor.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {ISwapFacility} from "src/interfaces/ISwapFacility.sol";

contract aUSTVault is Vault {

    IxAnchor public xAnchor;   
    AggregatorV3Interface public priceFeed;
    ISwapFacility public swapper; //Just set to non null value
    IERC20 public aUST;

    /* @dev UST balances are rigorously accounted for and adjusted when UST 
    is provided and removed from the system through actual transfers. It is *only* 
    updated to recoincile interest accrual when we are reasonably confident that the aUST
    balance is correct. */
    uint256 public lastUSTBalance;

    /* @dev aUST balances are accounted for by balanceOf() calls and must be treated
    as inherently untrusted because of the time gap between when aUST is made 
    and when it is actually reflected by the bridge transfer */
    uint256 public lastaUSTBalance;

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
        address _aUST
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);

        xAnchor = IxAnchor(_xanchor);
        priceFeed = AggregatorV3Interface(_pricefeed);
        aUST = IERC20(_aUST);
        underlying.approve(_xanchor, MAX_INT);
    }

    function setSwapper(address _swapper) public onlyOwner {
        swapper = ISwapFacility(_swapper);
        aUST.approve(_swapper, MAX_INT);
    }

    function max(uint a, uint b) internal pure returns (uint256) {
        return a < b ? b : a;
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
    function receiptPerUnderlying() public override view returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        uint256 _USTAmt = _getUSTaUST() * aUST.balanceOf(address(this)) / 1e18;
        _USTAmt = _USTAmt * 100001 / 100000; // Steals 0.1 bps to account for chainlink error and ensures 100% solvency
        _USTAmt = max(_USTAmt, lastUSTBalance); // This accounts for multiple deposits done between receiving aust from bridge
        return (1e18 * totalSupply) / _USTAmt;
    }

    function underlyingPerReceipt() public override view returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** underlyingDecimal;
        }
        uint256 _aUSTAmt = 1e18 * lastUSTBalance / _getUSTaUST();
        _aUSTAmt = _aUSTAmt * 100000 / 100001; // Steals 0.1 bps to account for chainlink error and ensures 100% solvency
        _aUSTAmt = max(_aUSTAmt, aUST.balanceOf(address(this))); // This accounts for multiple deposits done between receiving aust from bridge
        return 1e18 * swapper.getAmountOut(_aUSTAmt) / totalSupply; //No need to scale by 1e18 since chainlink pricefeed already scales
    }
    

    function _getValueOfUnderlyingPre() internal override returns (uint256) {
        return lastUSTBalance;
    }

    /* There is a chance _getValueOfUnderlyingPost() < _getValueOfUnderlyingPre()
        if a large UST deposit is made and compound is called before the aUST arrives
        in the vault. Hence the compound logic is adjusted to account for this  */
    function _getValueOfUnderlyingPost() internal override view returns (uint256) {
        return _getUSTaUST() * aUST.balanceOf(address(this)) / 1e18;
    }

    function totalHoldings() public override view returns (uint256) {
        return _getValueOfUnderlyingPost();
    }
    
    function _triggerDepositAction(uint256 amtOfUnderlying) internal override {
        lastaUSTBalance = aUST.balanceOf(address(this));
        /* One of two places where UST interest accrual is updated. Ensures monotonic increases 
        in case newly deposited aUST has not landed yet */
        lastUSTBalance = max(lastUSTBalance, _getUSTaUST() * lastaUSTBalance / 1e18);
        lastUSTBalance += amtOfUnderlying;
        xAnchor.depositStable(address(underlying), amtOfUnderlying);
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        swapper.swapAmountOut(amtToReturn);
        lastaUSTBalance = aUST.balanceOf(address(this));
        lastUSTBalance -= amtToReturn;
        /* Two of two places where UST interest accrual is updated. Ensures monotonic increases 
        in case newly deposited aUST has not landed yet */
        lastUSTBalance = max(lastUSTBalance, _getUSTaUST() * lastaUSTBalance / 1e18);
    }

    function _compound() internal override returns (uint256) {
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
            lastUSTBalance = (lastUSTBalance - adminAmt) - callerAmt;
            _triggerDepositAction(underlying.balanceOf(address(this))); //Maybe some dust left?
        }
        lastaUSTBalance = aUST.balanceOf(address(this));
     }


    // Emergency withdraw in case of previously failed operations
    // Notice that this address is the Terra address of the token
    function emergencyWithdraw(string calldata token) public onlyOwner {
        xAnchor.withdrawAsset(token);
    }

    // If something weird happens. Recoincile balances.
    function forceBalanceUpdate() external onlyOwner {
        lastaUSTBalance = aUST.balanceOf(address(this));
        lastUSTBalance = _getUSTaUST() * aUST.balanceOf(address(this)) / 1e18;
    }
}
