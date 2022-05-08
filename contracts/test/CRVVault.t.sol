// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/CRVVault.sol";
import "./TestERC20.sol";
import "./Utils.sol";


// This test covers integration for comp-like vaults

contract TestsCRVVault is DSTest {

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

    IERC20 constant CRV = IERC20(0x47536F17F4fF30e64A96a7555826b8f9e66ec468);
    IERC20 constant CRVLP = IERC20(0x1337BedC9D22ecbe766dF105c9623922A27963EC); //USDC
    address constant CRVWAVAX = 0x78dA10824F4029Adfb79669c4bd4F1962d08a0Bb;
    address constant CRVLPHolder = 0xBd48dd506E9179a757AE229d04745476ce6C2aad;

    address constant threePool = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;

    address constant joePair = 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1; // USDC-WAVAX
    address constant joeRouter = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address constant aave = 0x4F01AeD16D97E3aB5ab2B501154DC9bb0F1A5A2C;
    address constant aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    
    address constant aUSDC = 0x46A51127C3ce23fb7AB1DE06226147F446e4a857;
    CRVVault public vault;
    uint public underlyingBalance;
    function setUp() public {
        vault = new CRVVault();
        vault.initialize(
            address(CRVLP),
            "Vault",
            "VAULT",
            ADMINFEE,
            CALLERFEE,
            MAX_REINVEST_STALE,
            address(WAVAX),
            0x5B5CFE992AdAC0C9D48E05854B2d91C73a003858);

        vault.setJoeRouter(joeRouter);
        vault.setAAVE(aave, aaveV3);
        vault.setApprovals(address(WAVAX), joeRouter, MAX_INT);
        vault.setApprovals(address(USDC), joeRouter, MAX_INT);
        
        vault.setApprovals(address(WAVAX), aave, MAX_INT);
        vault.setApprovals(address(USDC), aave, MAX_INT);
        vault.setApprovals(address(CRVLP), 0x5B5CFE992AdAC0C9D48E05854B2d91C73a003858, MAX_INT);
        vault.setApprovals(address(USDC), threePool, MAX_INT);
        vault.setApprovals(aUSDC, threePool, MAX_INT);
        vault.setApprovals(joePair, joeRouter, MAX_INT);
        
        // Router.Node[] memory _path = new Router.Node[](2);
        // _path[0] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        // _path[1] = Router.Node(threePool, 3, address(USDC), address(CRVLP), 3, 1, -1);
        // vault.setRoute(address(WAVAX), address(CRVLP), _path);

        // Router.Node[] memory _path2 = new Router.Node[](3);
        // _path2[0] = Router.Node(CRVWAVAX, 1, address(CRV), address(WAVAX), 0, 0, 0);
        // _path2[1] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        // _path2[2] = Router.Node(threePool, 3, address(USDC), address(CRVLP), 3, 1, -1);
        // vault.setRoute(address(CRV), address(CRVLP), _path2);

        Router.Node[] memory _path = new Router.Node[](3);
        _path[0] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        _path[1] = Router.Node(address(0), 6, address(USDC), aUSDC, 0, 0, 0);
        _path[2] = Router.Node(threePool, 3, aUSDC, address(CRVLP), -3, 1, -1);
        vault.setRoute(address(WAVAX), address(CRVLP), _path);

        Router.Node[] memory _path2 = new Router.Node[](4);
        _path2[0] = Router.Node(CRVWAVAX, 1, address(CRV), address(WAVAX), 0, 0, 0);
        _path2[1] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        _path2[2] = Router.Node(address(0), 6, address(USDC), aUSDC, 0, 0, 0);
        _path2[3] = Router.Node(threePool, 3, aUSDC, address(CRVLP), -3, 1, -1);
        vault.setRoute(address(CRV), address(CRVLP), _path2);

        vm.startPrank(wavaxHolder);
        WAVAX.transfer(address(this), WAVAX.balanceOf(wavaxHolder));
        vm.stopPrank();
        vm.startPrank(usdcHolder);
        USDC.transfer(address(this), USDC.balanceOf(usdcHolder));
        vm.stopPrank();
        vm.startPrank(CRVLPHolder);
        CRVLP.transfer(address(this), CRVLP.balanceOf(CRVLPHolder));
        vm.stopPrank();

        vault.pushRewardToken(address(WAVAX));
        vault.pushRewardToken(address(CRV));

        CRVLP.approve(address(vault), MAX_INT);
        underlyingBalance=CRVLP.balanceOf(address(this));
        vm.warp(1647861775-80 days);
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
        uint preBalanceToken = CRVLP.balanceOf(address(this));
        vault.redeem(preBalanceVault);
        uint postBalanceVault = vault.balanceOf(address(this));
        uint postBalanceToken = CRVLP.balanceOf(address(this));
        console.log(postBalanceVault, preBalanceVault);
        console.log(postBalanceToken, preBalanceToken);
        assertTrue(postBalanceVault == preBalanceVault - (amt - vault.FIRST_DONATION()));
        assertTrue(postBalanceToken == preBalanceToken + (amt - vault.FIRST_DONATION()));
    }
    function testVanillaDepositNCompoundOnly(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<1e5*vault.MIN_FIRST_MINT()) {
            return 0;
        }
        vault.deposit(amt);
        uint preBalance = vault.underlyingPerReceipt();
        vm.warp(block.timestamp+100 days);
        vault.compound();
        uint postBalance = vault.underlyingPerReceipt();
        assertTrue(postBalance > preBalance);
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
        assertTrue(amt < CRVLP.balanceOf(address(this)));
        return amt;
    }
}
