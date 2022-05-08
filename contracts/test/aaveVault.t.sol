// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/aaveVault.sol";
import "./TestERC20.sol";
import "./Utils.sol";


// This test covers integration for comp-like vaults

contract TestaaveVault is DSTest {

    uint constant ADMINFEE=100;
    uint constant CALLERFEE=10;
    uint constant MAX_REINVEST_STALE= 1 hours;
    uint constant MAX_INT= 2**256 - 1;

    uint public MIN_FIRST_MINT;
    uint public FIRST_DONATION;
    uint public decimalCorrection;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    IERC20 constant USDC = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664); //USDC
    address constant usdcHolder = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    IERC20 constant WAVAX = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7); //WAVAX
    address constant wavaxHolder = 0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB; 

    IERC20 constant avUSDC = IERC20(0x46A51127C3ce23fb7AB1DE06226147F446e4a857); //USDC
    address constant avusdcHolder = 0xc5ed2333f8a2C351fCA35E5EBAdb2A82F5d254C3;

    address constant joePair = 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1; // USDC-WAVAX
    address constant joeRouter = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address constant aave = 0x4F01AeD16D97E3aB5ab2B501154DC9bb0F1A5A2C;
    address constant aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    
    aaveVault public vault;
    uint public underlyingBalance;
    function setUp() public {
        vault = new aaveVault();
        vault.initialize(
            address(avUSDC),
            "Vault",
            "VAULT",
            ADMINFEE,
            CALLERFEE,
            MAX_REINVEST_STALE,
            address(WAVAX),
            0x01D83Fe6A10D2f2B7AF17034343746188272cAc9
            );
        MIN_FIRST_MINT=vault.MIN_FIRST_MINT();
        decimalCorrection = (10 ** (18-avUSDC.decimals()));
        FIRST_DONATION=vault.FIRST_DONATION()/decimalCorrection;
        vault.setJoeRouter(joeRouter);
        vault.setAAVE(aave, aaveV3);
        vault.setApprovals(address(WAVAX), joeRouter, MAX_INT);
        vault.setApprovals(address(USDC), joeRouter, MAX_INT);
        vault.setApprovals(address(WAVAX), aave, MAX_INT);
        vault.setApprovals(address(USDC), aave, MAX_INT);
        vault.setApprovals(joePair, joeRouter, MAX_INT);

        // vault.setApprovals(address(USDC), address(avUSDC), MAX_INT);
        Router.Node[] memory _path = new Router.Node[](2);
        _path[0] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        _path[1] = Router.Node(address(0), 6, address(USDC), address(avUSDC), 0, 0, 0);
        vault.setRoute(address(WAVAX), address(avUSDC), _path);

        // Router.Node[] memory _path2 = new Router.Node[](3);
        // _path2[0] = Router.Node(QIWAVAX, 1, address(QI), address(WAVAX), 0, 0, 0);
        // _path2[1] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        // _path2[2] = Router.Node(address(0), 7, address(USDC), address(avUSDC), 0, 0, 0);
        // vault.setRoute(address(QI), address(avUSDC), _path2);

        vm.startPrank(wavaxHolder);
        WAVAX.transfer(address(this), WAVAX.balanceOf(wavaxHolder));
        vm.stopPrank();
        vm.startPrank(usdcHolder);
        USDC.transfer(address(this), USDC.balanceOf(usdcHolder));
        vm.stopPrank();
        vm.startPrank(avusdcHolder);
        avUSDC.transfer(address(this), 1e6);
        vm.stopPrank();
        
        // vault.pushRewardToken(address(QI));
        vault.pushRewardToken(address(WAVAX));

        avUSDC.approve(address(vault), MAX_INT);
        underlyingBalance=avUSDC.balanceOf(address(this));
        // vm.warp(1647861775+10 days);
        // vm.warp(block.timestamp+10 days);
    }


    function testVanillaDepositOnly(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<MIN_FIRST_MINT) {
            return 0;
        }
        uint preBalance = vault.balanceOf(address(this));
        vault.deposit(amt);
        uint postBalance = vault.balanceOf(address(this))/decimalCorrection;
        console.log(postBalance);
        assertTrue(postBalance == preBalance + amt - FIRST_DONATION);
        return amt;
    }

    function testViewFuncs1(uint96 amt) public {
        if (amt > underlyingBalance || amt<MIN_FIRST_MINT) {
            return;
        }
        assertTrue(vault.receiptPerUnderlying() == 1e18*decimalCorrection);
        assertTrue(vault.underlyingPerReceipt() == 10**avUSDC.decimals());
        assertTrue(vault.totalSupply() == 0);
        vault.deposit(amt);
        assertTrue(vault.totalSupply() == amt*decimalCorrection);
        assertTrue(vault.receiptPerUnderlying() == 1e18*decimalCorrection);
        assertTrue(vault.underlyingPerReceipt() == 10**avUSDC.decimals());
    }


    function testVanillaDepositNredeem(uint96 amt) public {
        if (amt > underlyingBalance || amt<MIN_FIRST_MINT) {
            return;
        }
        vault.deposit(amt);
        uint preBalanceVault = vault.balanceOf(address(this))/decimalCorrection;
        uint preBalanceToken = avUSDC.balanceOf(address(this));
        vault.redeem(preBalanceVault*decimalCorrection);
        uint postBalanceVault = vault.balanceOf(address(this));
        uint postBalanceToken = avUSDC.balanceOf(address(this));
        console.log(postBalanceVault, preBalanceVault);
        console.log(postBalanceToken, preBalanceToken);
        assertTrue(postBalanceVault == 0);
        assertTrue(postBalanceToken == preBalanceToken + amt - FIRST_DONATION);
    }
    function testVanillaDepositNCompoundOnly(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<MIN_FIRST_MINT) {
            return 0;
        }
        vault.deposit(amt);
        uint preBalance = avUSDC.balanceOf(address(vault));
        vm.warp(block.timestamp+100 days);
        vault.compound();
        uint postBalance = avUSDC.balanceOf(address(vault));
        console.log(preBalance);
        console.log(postBalance);
        assertTrue(postBalance > preBalance);
        return amt;
    }
    function testVanillaDepositNCompoundredeem(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<MIN_FIRST_MINT) {
            return 0;
        }
        vault.deposit(amt);
        vm.warp(block.timestamp+100 days);
        vault.compound();
        vault.redeem(vault.balanceOf(address(this)));
        assertTrue(amt < avUSDC.balanceOf(address(this)));
        return amt;
    }
}
