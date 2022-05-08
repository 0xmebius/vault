// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/sJOEVault.sol";
import "./TestERC20.sol";
import "./Utils.sol";


// This test covers integration for comp-like vaults

contract TestsJOEVault is DSTest {

    uint constant ADMINFEE=100;
    uint constant CALLERFEE=10;
    uint constant MAX_REINVEST_STALE= 1 hours;
    uint constant MAX_INT= 2**256 - 1;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    IERC20 constant USDC = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664); //USDC
    address constant usdcHolder = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    IERC20 constant WAVAX = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7); //WAVAX
    address constant wavaxHolder = 0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB; 

    IERC20 constant JLP = IERC20(0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1); //USDC
    address constant JLPHolder = 0x8361dde63F80A24256657D19a5B659F2FB9df2aB;

    IERC20 constant JOE = IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd); //USDC
    address constant JOEWAVAX = 0x454E67025631C065d3cFAD6d71E6892f74487a15;
    address constant JOEHolder = 0x279f8940ca2a44C35ca3eDf7d28945254d0F0aE6;

    address constant joePair = 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1; // USDC-WAVAX
    address constant joeRouter = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address constant aave = 0x4F01AeD16D97E3aB5ab2B501154DC9bb0F1A5A2C;
    address constant aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    
    sJOEVault public vault;
    uint public underlyingBalance;
    function setUp() public {
        vault = new sJOEVault();
        vault.initialize(
            address(JOE),
            "Vault",
            "VAULT",
            ADMINFEE,
            CALLERFEE,
            MAX_REINVEST_STALE,
            address(WAVAX),
            0x1a731B2299E22FbAC282E7094EdA41046343Cb51);

        vault.setJoeRouter(joeRouter);
        vault.setAAVE(aave, aaveV3);
        vault.setApprovals(address(WAVAX), joeRouter, MAX_INT);
        vault.setApprovals(address(USDC), joeRouter, MAX_INT);
        vault.setApprovals(address(WAVAX), aave, MAX_INT);
        vault.setApprovals(address(USDC), aave, MAX_INT);
        vault.setApprovals(joePair, joeRouter, MAX_INT);

        // vault.setApprovals(address(USDC), address(qUSDC), MAX_INT);
        
        Router.Node[] memory _path = new Router.Node[](2);
        
        _path[0] = Router.Node(joePair, 1, address(USDC), address(WAVAX), 0, 0, 0);
        _path[1] = Router.Node(JOEWAVAX, 1, address(WAVAX), address(JOE), 0, 0, 0);
        vault.setRoute(address(USDC), address(JOE), _path);

        // Router.Node[] memory _path2 = new Router.Node[](3);
        // _path2[0] = Router.Node(QIWAVAX, 1, address(QI), address(WAVAX), 0, 0, 0);
        // _path2[1] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        // _path2[2] = Router.Node(address(qUSDC), 7, address(USDC), address(qUSDC), 0, 0, 0);
        // vault.setRoute(address(QI), address(qUSDC), _path2);

        vm.startPrank(wavaxHolder);
        WAVAX.transfer(address(this), WAVAX.balanceOf(wavaxHolder));
        vm.stopPrank();
        vm.startPrank(usdcHolder);
        USDC.transfer(address(this), USDC.balanceOf(usdcHolder));
        vm.stopPrank();
        vm.startPrank(JOEHolder);
        JOE.transfer(address(this), JOE.balanceOf(JOEHolder));
        vm.stopPrank();

        // vault.pushRewardToken(address(QI));
        vault.pushRewardToken(address(USDC));

        JOE.approve(address(vault), MAX_INT);
        underlyingBalance=JOE.balanceOf(address(this));
        vm.warp(1647861775+20 days);
    }


    function testVanillaDeposit(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return 0;
        }
        uint preBalance = vault.balanceOf(address(this));
        vault.deposit(amt);
        uint postBalance = vault.balanceOf(address(this));
        assertTrue(postBalance == preBalance + amt - vault.FIRST_DONATION());
        return amt;
    }

    function testViewFuncs1(uint96 amt) public {
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        assertTrue(vault.receiptPerUnderlying() == 1e18);
        assertTrue(vault.underlyingPerReceipt() == 1e18);
        assertTrue(vault.totalSupply() == 0);
        vault.deposit(amt);
        assertTrue(vault.totalSupply() == amt);
        assertTrue(vault.receiptPerUnderlying() == 1e18);
        assertTrue(vault.underlyingPerReceipt() == 1e18);
    }


    function testVanillaDepositNredeem(uint96 amt) public {
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        vault.deposit(amt);
        uint preBalanceVault = vault.balanceOf(address(this));
        uint preBalanceToken = JOE.balanceOf(address(this));
        vault.redeem(preBalanceVault);
        uint postBalanceVault = vault.balanceOf(address(this));
        uint postBalanceToken = JOE.balanceOf(address(this));
        console.log(postBalanceVault, preBalanceVault);
        console.log(postBalanceToken, preBalanceToken);
        assertTrue(postBalanceVault == preBalanceVault - (amt - vault.FIRST_DONATION()));
        assertTrue(postBalanceToken == preBalanceToken + (amt - vault.FIRST_DONATION()));
    }
    function testVanillaDepositNCompound(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return 0;
        }
        vault.deposit(amt);
        uint preBalance = vault.underlyingPerReceipt();
        vm.warp(block.timestamp+100 days);
        vault.compound();
        uint postBalance = vault.underlyingPerReceipt();
        assertTrue(postBalance >= preBalance);
        return amt;
    }
    function testVanillaDepositNCompoundredeem(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return 0;
        }
        vault.deposit(amt);
        vm.warp(block.timestamp+100 days);
        vault.compound();
        vault.redeem(vault.balanceOf(address(this)));
        assertTrue(amt < JOE.balanceOf(address(this)));
        return amt;
    }
}
