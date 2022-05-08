// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/Vault.sol";
import "./TestERC20.sol";
import "./Utils.sol";


// This test covers basic functionality of the Vault contract
// Basic redeem and deposit functionality
// Basic token transfer/approval functionality
// Basic proportional distribution when new underlying tokens are minted to vault
// TODO: Test permit functions

contract TestBasicVault is DSTest {

    uint constant ADMINFEE=100;
    uint constant CALLERFEE=10;
    uint constant MAX_REINVEST_STALE= 1 hours;
    address constant WAVAX = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    TestERC20 public underlying;
    Vault public vault;
    function setUp() public {
        underlying = new TestERC20("MYTOKEN", "TEST", 18);
        vault = new Vault();
        vault.initialize(
            address(underlying),
            "Vault",
            "VAULT",
            ADMINFEE,
            CALLERFEE,
            MAX_REINVEST_STALE,
            WAVAX);
        vm.warp(1650534735);
    }

    function testPushRewardToken() public {
        uint numRewardTokensBefore = vault.numRewardTokens();
        vault.pushRewardToken(address(1));
        uint numRewardTokensAfter = vault.numRewardTokens();
        assertTrue(numRewardTokensAfter == numRewardTokensBefore + 1);
        assertTrue(vault.getRewardToken(numRewardTokensBefore) == address(1));
    }

    function testDeprecateRewardToken() public {
        testPushRewardToken();
        uint numRewardTokensBefore = vault.numRewardTokens();
        vault.deprecateRewardToken(numRewardTokensBefore-1);
        uint numRewardTokensAfter = vault.numRewardTokens();
        assertTrue(numRewardTokensAfter == numRewardTokensBefore);
        assertTrue(vault.getRewardToken(numRewardTokensBefore-1) == address(0));
    }

    function testVanillaDeposit(uint96 amt) public returns (uint) {
        if (amt<vault.MIN_FIRST_MINT()) {
            return 0;
        }
        uint preBalance = vault.balanceOf(address(this));
        deposit(amt, address(this));
        uint postBalance = vault.balanceOf(address(this));
        assertTrue(postBalance == preBalance + amt - vault.FIRST_DONATION());
        return amt;
    }
    function deposit(uint96 amt, address from) public returns (uint) {
        // if (amt<vault.MIN_FIRST_MINT()) {
        //     return 0;
        // }
        vm.stopPrank();
        vm.startPrank(from);
        underlying.mint(from, amt);
        underlying.approve(address(vault), amt);
        uint preBalance = vault.balanceOf(from);
        vault.deposit(amt);
        uint postBalance = vault.balanceOf(from);
        vm.stopPrank();
        return postBalance-preBalance;
    }

    function testViewFuncs1(uint96 amt) public {
        if (amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        assertTrue(vault.receiptPerUnderlying() == 1e18);
        assertTrue(vault.underlyingPerReceipt() == 1e18);
        assertTrue(vault.totalSupply() == 0);
        testVanillaDeposit(amt);
        assertTrue(vault.totalSupply() == amt);
        assertTrue(vault.receiptPerUnderlying() == 1e18);
        assertTrue(vault.underlyingPerReceipt() == 1e18);
    }

    function testViewFuncs2(uint96 amt) public {
        if (amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        assertTrue(vault.receiptPerUnderlying() == 1e18);
        assertTrue(vault.underlyingPerReceipt() == 1e18);
        assertTrue(vault.totalSupply() == 0);
        testVanillaDeposit(amt);
        underlying.mint(address(vault), amt);
        assertTrue(vault.totalSupply() == amt);
        assertTrue(vault.receiptPerUnderlying() == 5e17);
        assertTrue(vault.underlyingPerReceipt() ==  2e18);
    }

    function testVanillaDepositNredeem(uint96 amt) public {
        if (amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        testVanillaDeposit(amt);
        uint preBalanceVault = vault.balanceOf(address(this));
        uint preBalanceToken = underlying.balanceOf(address(this));
        vault.redeem(preBalanceVault);
        uint postBalanceVault = vault.balanceOf(address(this));
        uint postBalanceToken = underlying.balanceOf(address(this));
        console.log(postBalanceVault, preBalanceVault);
        console.log(postBalanceToken, preBalanceToken);
        assertTrue(postBalanceVault == preBalanceVault - (amt - vault.FIRST_DONATION()));
        assertTrue(postBalanceToken == preBalanceToken + (amt - vault.FIRST_DONATION()));
    }

    function testVanillaDepositNredeem2Ppl(uint96 amt1, uint96 amt2) public {
        if (amt1<vault.MIN_FIRST_MINT() || amt2 == 0) {
            return;
        }
        vm.stopPrank();
        vm.startPrank(address(1));
        deposit(amt1, address(1));
        console.log(vault.receiptPerUnderlying());
        console.log(vault.underlyingPerReceipt());
        uint preBalanceVault1 = vault.balanceOf(address(1));
        uint preBalanceToken1 = underlying.balanceOf(address(1));
        vm.stopPrank();
        vm.startPrank(address(2));
        deposit(amt2, address(2));
        console.log(vault.receiptPerUnderlying());
        console.log(vault.underlyingPerReceipt());
        uint preBalanceVault2 = vault.balanceOf(address(2));
        uint preBalanceToken2 = underlying.balanceOf(address(2));
        vm.stopPrank();
        vm.startPrank(address(1));
        vault.redeem(preBalanceVault1);
        console.log(vault.receiptPerUnderlying());
        console.log(vault.underlyingPerReceipt());
        uint postBalanceVault1 = vault.balanceOf(address(1));
        uint postBalanceToken1 = underlying.balanceOf(address(1));
        assertTrue(postBalanceVault1 == preBalanceVault1 - (amt1- vault.FIRST_DONATION()));
        assertTrue(postBalanceToken1 == preBalanceToken1 + (amt1- vault.FIRST_DONATION()));
        vm.stopPrank();
        vm.startPrank(address(2));
        vault.redeem(preBalanceVault2);
        console.log(vault.receiptPerUnderlying());
        console.log(vault.underlyingPerReceipt());
        uint postBalanceVault2 = vault.balanceOf(address(2));
        uint postBalanceToken2 = underlying.balanceOf(address(2));
        assertTrue(postBalanceVault2 == preBalanceVault2 - amt2);
        assertTrue(postBalanceToken2 == preBalanceToken2 + amt2);
    }

    function testVanillaDepositNredeemFor(uint96 amt) public {
        if (amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        testVanillaDeposit(amt);
        uint preBalanceVault = vault.balanceOf(address(this));
        uint preBalanceToken = underlying.balanceOf(address(1));
        vault.approve(address(1), amt);
        address original = address(this);
        vm.prank(address(1));
        vault.redeemFor(preBalanceVault, original, address(this));
        uint postBalanceVault = vault.balanceOf(address(this));
        uint postBalanceToken = underlying.balanceOf(original);
        assertTrue(postBalanceVault == preBalanceVault - (amt - vault.FIRST_DONATION()));
        assertTrue(postBalanceToken == preBalanceToken + (amt - vault.FIRST_DONATION()));
    }

    function testProportionalDepositNredeem() public {
        uint96 amt = 1e18;
        uint96 amtToMint = 200e18;
        if (amt == 0) {
            return;
        }
        testVanillaDeposit(amt);
        uint preBalanceVault = vault.balanceOf(address(this));
        uint preBalanceToken = underlying.balanceOf(address(this));
        underlying.mint(address(vault), amtToMint);
        vault.redeem(preBalanceVault);
        uint postBalanceToken = underlying.balanceOf(address(this));
        console.log(postBalanceToken, preBalanceToken);
        assertTrue(amt == preBalanceVault + vault.FIRST_DONATION());
        Utils.assertSmallDiff(postBalanceToken, preBalanceToken + amt + amtToMint - vault.FIRST_DONATION());
    }

    function testProportionalDepositNredeem2Ppl(uint96 amt1, uint96 amt2) public {
        if (amt1<vault.MIN_FIRST_MINT() || amt2 < amt1/1e4) {
            return;
        }
        uint amtToMint;
        unchecked {
            amtToMint = amt1+amt2;
        }
        
        vm.startPrank(address(1));
        deposit(amt1, address(1));
        uint preBalanceVault1 = vault.balanceOf(address(1));
        
        underlying.mint(address(vault), amtToMint);
        vm.stopPrank();
        vm.startPrank(address(2));
        deposit(amt2, address(2));
        uint preBalanceVault2 = vault.balanceOf(address(2));
        vm.stopPrank();
        vm.startPrank(address(1));
        vault.redeem(preBalanceVault1);
        uint postBalanceVault1 = vault.balanceOf(address(1));
        uint postBalanceToken1 = underlying.balanceOf(address(1));
        assertTrue(postBalanceVault1 == 0);
        console.log(postBalanceVault1, postBalanceToken1, amt1, amtToMint);
        assertTrue(Utils.assertSmallDiff(postBalanceToken1,  amt1 + amtToMint));

        vm.stopPrank();
        vm.startPrank(address(2));
        vault.redeem(preBalanceVault2);
        uint postBalanceVault2 = vault.balanceOf(address(2));
        uint postBalanceToken2 = underlying.balanceOf(address(2));
        assertTrue(postBalanceVault2 == 0);
        console.log(postBalanceToken2, amt2);
        assertTrue(Utils.assertSmallDiff(postBalanceToken2, amt2));
    }

    function testFailProportionalDepositNredeem2Ppl(uint96 amt1, uint96 amt2) public {
        if (amt1<vault.MIN_FIRST_MINT() || amt2 == 0) {
            revert();
        }
        if (amt2 > amt1/1e5) {
            revert();
        }
        uint amtToMint;
        unchecked {
            amtToMint = amt1+amt2;
        }
        
        vm.startPrank(address(1));
        deposit(amt1, address(1));
        uint preBalanceVault1 = vault.balanceOf(address(1));
        
        underlying.mint(address(vault), amtToMint);
        vm.stopPrank();
        vm.startPrank(address(2));
        deposit(amt2, address(2));
        uint preBalanceVault2 = vault.balanceOf(address(2));
        vm.stopPrank();
        vm.startPrank(address(1));
        vault.redeem(preBalanceVault1);
        vault.redeem(preBalanceVault2);
    }
    

}
