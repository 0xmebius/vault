// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/PSM.sol";
import "./TestERC20.sol";
import "./Utils.sol";

import "src/integrations/aUSDCPSMStrategy.sol";

import "src/interfaces/IYetiVaultToken.sol";

import "src/testContracts/TestStrategyDummy.sol";

interface IYetiController {
    function addValidYUSDMinter(address minter) external;
}

interface TransparentUpgradeableProxy {
    function upgradeTo(address newImplementation) external;
}


contract PSMTest is DSTest {

    Vm public constant vm = Vm(HEVM_ADDRESS);

    IERC20 constant USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); //USDC Native

    IYUSDToken constant YUSD = IYUSDToken(0x111111111111ed1D73f860F57b2798b683f2d325);

    address constant USDC_HOLDER = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address constant YUSD_HOLDER = 0xFFffFfffFff5d3627294FeC5081CE5C5D7fA6451;
    address constant FEE_RECIPIENT = address(1234);
    address constant MINT_RECIPIENT = address(12345);

    uint256 internal constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    PSM psm;
    address burner;
    TestStrategyDummy strategy;
    

    // Can add valid minter (Later will be timelock)
    address constant treasury = 0xf572455BE31BF54Cc7D0c6D69B60813171bb7b12;
    address constant PROXY_ADMIN = 0x35D6bA8f18cEE7578f94e13B338D989806800a7a;
    // through controller
    IYetiController constant yeti_controller = IYetiController(0xcCCCcCccCCCc053fD8D1fF275Da4183c2954dBe3);
    address constant TMR = 0x00000000000d9c2f60d8e82F2d1C2bed5008DD7d;

    function setUp() public {
        strategy = new TestStrategyDummy();
        psm = new PSM();

        // Upgrade TroveManagerRedemptions to a version with burn, and 
        // add validBurner access control to YetiController. 
        // Upgrade the contracts to the new version
        // temp addresses for pending upgrade
        address YC_new = 0xf7DA8a8310aB182B52E8082C3d3c256d12d6Cd66;
        address TMR_new = 0xda67834515e4eE0C2d18f3b81DeBef2CF17C9608;

        vm.startPrank(PROXY_ADMIN);
        TransparentUpgradeableProxy(address(yeti_controller)).upgradeTo(YC_new);
        TransparentUpgradeableProxy(TMR).upgradeTo(TMR_new);

        vm.stopPrank();

        // Will be owner of the deployed PSM contract
        vm.startPrank(treasury);

        strategy.initialize(address(psm));
        psm.initialize(
            TMR,
            address(strategy),
            FEE_RECIPIENT,
            1000000e18, // 10m
            100 // 1% fee
        );

        // Add PSM as valid minter / burner
        yeti_controller.addValidYUSDMinter(address(psm));
        vm.stopPrank();
    }


    /// ===========================================
    /// Mint tests
    /// ===========================================


    // Basic PSM YUSD minting test
    // Test minting YUSD using a certain amount of USDC 
    // Should charge the correct fee amount. 
    // Fee should be sent to fee recipient for correct amount. 
    // YUSD total supply increases, user receives YUSD. 
    // User loses USDC for amount of YUSD plus fee
    // Strategy holds USDC for correct amount
    function testMintBasic() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 100e6;
        uint EXPECTED_FEE = 1e6;
        uint EXPECTED_YUSD_MINTED = 99e18;
        // Check YUSD and USDC balances before tx
        uint feeRecipientUSDCBefore = USDC.balanceOf(FEE_RECIPIENT);
        uint mintRecipientYUSDBefore = YUSD.balanceOf(MINT_RECIPIENT);
        uint strategyUSDCBefore = USDC.balanceOf(address(strategy));
        uint totalSupplyBefore = YUSD.totalSupply();
        uint usdcHolderUSDCBefore = USDC.balanceOf(USDC_HOLDER);

        // Mint YUSD for MINT_AMOUNT
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);

        // Check YUSD and USDC balances after tx
        uint feeRecipientUSDCAfter = USDC.balanceOf(FEE_RECIPIENT);
        assertTrue(feeRecipientUSDCAfter == feeRecipientUSDCBefore + EXPECTED_FEE, "FeeRecipient fail");
        uint mintRecipientYUSDAfter = YUSD.balanceOf(MINT_RECIPIENT);
        assertTrue(mintRecipientYUSDAfter == mintRecipientYUSDBefore + EXPECTED_YUSD_MINTED, "mint recipient fail");
        uint strategyUSDCAfter = USDC.balanceOf(address(strategy));
        assertTrue(strategyUSDCAfter == strategyUSDCBefore + MINT_AMOUNT_USDC - EXPECTED_FEE, "strategy usdc deposit failed");
        uint reportedStrategyUSDCAfter = strategy.totalHoldings();
        assertTrue(strategyUSDCAfter == reportedStrategyUSDCAfter, "strategy usdc reporting failed");
        uint totalSupplyAfter = YUSD.totalSupply();
        assertTrue(totalSupplyAfter == totalSupplyBefore + EXPECTED_YUSD_MINTED, "total supply fail");
        uint usdcHolderUSDCAfter = USDC.balanceOf(USDC_HOLDER);
        assertTrue(usdcHolderUSDCAfter == usdcHolderUSDCBefore - MINT_AMOUNT_USDC, "usdc holder balance didn't decrease");
        uint YUSDContractDebt = psm.YUSDContractDebt();
        assertTrue(YUSDContractDebt == EXPECTED_YUSD_MINTED);
    }


    // Swap fee change test 
    // Same as first test but with a change of fees
    // Also set new fee recipient
    function testMintBasicChangeFee() public {

        address NEW_FEE_RECIPIENT = address(123451234123);

        vm.startPrank(treasury);
        psm.setFee(200); // 2% fee
        psm.setFeeRecipient(NEW_FEE_RECIPIENT);
        vm.stopPrank();

        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 100e6;
        uint EXPECTED_FEE = 2e6;
        uint EXPECTED_YUSD_MINTED = 98e18;
        // Check YUSD and USDC balances before tx
        uint feeRecipientUSDCBefore = USDC.balanceOf(NEW_FEE_RECIPIENT);
        uint mintRecipientYUSDBefore = YUSD.balanceOf(MINT_RECIPIENT);
        uint strategyUSDCBefore = USDC.balanceOf(address(strategy));
        uint totalSupplyBefore = YUSD.totalSupply();
        uint usdcHolderUSDCBefore = USDC.balanceOf(USDC_HOLDER);

        // Mint YUSD for MINT_AMOUNT
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);

        // Check YUSD and USDC balances after tx
        uint feeRecipientUSDCAfter = USDC.balanceOf(NEW_FEE_RECIPIENT);
        assertTrue(feeRecipientUSDCAfter == feeRecipientUSDCBefore + EXPECTED_FEE, "FeeRecipient fail");
        uint mintRecipientYUSDAfter = YUSD.balanceOf(MINT_RECIPIENT);
        assertTrue(mintRecipientYUSDAfter == mintRecipientYUSDBefore + EXPECTED_YUSD_MINTED, "mint recipient fail");
        uint strategyUSDCAfter = USDC.balanceOf(address(strategy));
        assertTrue(strategyUSDCAfter == strategyUSDCBefore + MINT_AMOUNT_USDC - EXPECTED_FEE, "strategy usdc deposit failed");
        uint reportedStrategyUSDCAfter = strategy.totalHoldings();
        assertTrue(strategyUSDCAfter == reportedStrategyUSDCAfter, "strategy usdc reporting failed");
        uint totalSupplyAfter = YUSD.totalSupply();
        assertTrue(totalSupplyAfter == totalSupplyBefore + EXPECTED_YUSD_MINTED, "total supply fail");
        uint usdcHolderUSDCAfter = USDC.balanceOf(USDC_HOLDER);
        assertTrue(usdcHolderUSDCAfter == usdcHolderUSDCBefore - MINT_AMOUNT_USDC, "usdc holder balance didn't decrease");
        uint YUSDContractDebt = psm.YUSDContractDebt();
        assertTrue(YUSDContractDebt == EXPECTED_YUSD_MINTED);
    }

    // YUSD Debt limit test minting
    function testMintDebtLimitChange() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Set new limit to 1900
        vm.startPrank(treasury);
        psm.setDebtLimit(1900e18);
        vm.stopPrank();

        // Try again for 1000
        vm.startPrank(USDC_HOLDER);
        vm.expectRevert("Cannot mint more than PSM Debt limit");
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Mint less, should go through
        vm.startPrank(USDC_HOLDER);
        psm.mintYUSD(MINT_AMOUNT_USDC / 2, MINT_RECIPIENT);
    }


    /// ===========================================
    /// Redeem tests
    /// ===========================================


    // Basic PSM YUSD redeem test 
    function testRedeemBasic() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Now the PSM should have 1000 USDC in it 
        // Try to redeem 100 YUSD
        uint REDEEM_AMOUNT_YUSD = 100e18;
        uint EXPECTED_FEE = 1e18;
        uint EXPECTED_YUSD_BURNED = 99e18;
        uint EXPECTED_USDC_REDEEMED = 99e6;

        // Check YUSD and USDC balances before tx
        uint feeRecipientYUSDBefore = YUSD.balanceOf(FEE_RECIPIENT);
        uint redeemRecipientUSDCBefore = USDC.balanceOf(MINT_RECIPIENT);
        uint strategyUSDCBefore = USDC.balanceOf(address(strategy));
        uint totalSupplyBefore = YUSD.totalSupply();
        uint yusdHolderYUSDBefore = YUSD.balanceOf(YUSD_HOLDER);

        // Redeem YUSD for REDEEM_AMOUNT
        vm.startPrank(YUSD_HOLDER);
        YUSD.approve(address(psm), MAX_UINT);
        psm.redeemYUSD(REDEEM_AMOUNT_YUSD, MINT_RECIPIENT);

        // Check YUSD and USDC balances after tx
        uint feeRecipientYUSDAfter = YUSD.balanceOf(FEE_RECIPIENT);
        assertTrue(feeRecipientYUSDAfter == feeRecipientYUSDBefore + EXPECTED_FEE, "FeeRecipient fail");
        uint redeemRecipientUSDCAfter = USDC.balanceOf(MINT_RECIPIENT);
        assertTrue(redeemRecipientUSDCAfter == redeemRecipientUSDCBefore + EXPECTED_USDC_REDEEMED, "mint recipient fail");
        uint strategyUSDCAfter = USDC.balanceOf(address(strategy));
        assertTrue(strategyUSDCAfter == strategyUSDCBefore - EXPECTED_USDC_REDEEMED, "strategy usdc deposit failed");
        uint reportedStrategyUSDCAfter = strategy.totalHoldings();
        assertTrue(strategyUSDCAfter == reportedStrategyUSDCAfter, "strategy usdc reporting failed");
        uint totalSupplyAfter = YUSD.totalSupply();
        assertTrue(totalSupplyAfter == totalSupplyBefore - EXPECTED_YUSD_BURNED, "total supply fail");
        uint yusdHolderYUSDAfter = YUSD.balanceOf(YUSD_HOLDER);
        assertTrue(yusdHolderYUSDAfter == yusdHolderYUSDBefore - REDEEM_AMOUNT_YUSD, "usdc holder balance didn't decrease");
        uint YUSDContractDebt = psm.YUSDContractDebt();
        // uint EXPECTED_TOTAL_CONTRACT_DEBT_AFTER_REDEEM = 1000e18 * 99 / 100 - 99e18; stack too deep
        // Original mint amount - redeem amount, in USDC
        assertTrue(YUSDContractDebt == 1000e18 * 99 / 100 - EXPECTED_YUSD_BURNED, "Contract debt doesn't line up");
    }


    // Change fee PSM YUSD Redeem test
    function testRedeemBasicChangeFee() public {
        // From USDC holder, mint in PSM
        // uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(1000e6, MINT_RECIPIENT);
        vm.stopPrank();

        address NEW_FEE_RECIPIENT = address(123451234123);

        vm.startPrank(treasury);
        psm.setFee(200); // 2% fee
        psm.setFeeRecipient(NEW_FEE_RECIPIENT);
        vm.stopPrank();

        // Now the PSM should have 1000 USDC in it 
        // Try to redeem 100 YUSD
        uint REDEEM_AMOUNT_YUSD = 100e18;
        uint EXPECTED_FEE = 2e18;
        uint EXPECTED_YUSD_BURNED = 98e18;
        uint EXPECTED_USDC_REDEEMED = 98e6;

        // Check YUSD and USDC balances before tx
        uint feeRecipientYUSDBefore = YUSD.balanceOf(NEW_FEE_RECIPIENT);
        uint redeemRecipientUSDCBefore = USDC.balanceOf(MINT_RECIPIENT);
        uint strategyUSDCBefore = USDC.balanceOf(address(strategy));
        uint totalSupplyBefore = YUSD.totalSupply();
        uint yusdHolderYUSDBefore = YUSD.balanceOf(YUSD_HOLDER);

        // Redeem YUSD for REDEEM_AMOUNT
        vm.startPrank(YUSD_HOLDER);
        YUSD.approve(address(psm), MAX_UINT);
        psm.redeemYUSD(REDEEM_AMOUNT_YUSD, MINT_RECIPIENT);

        // Check YUSD and USDC balances after tx
        uint feeRecipientYUSDAfter = YUSD.balanceOf(NEW_FEE_RECIPIENT);
        assertTrue(feeRecipientYUSDAfter == feeRecipientYUSDBefore + EXPECTED_FEE, "FeeRecipient fail");
        uint redeemRecipientUSDCAfter = USDC.balanceOf(MINT_RECIPIENT);
        assertTrue(redeemRecipientUSDCAfter == redeemRecipientUSDCBefore + EXPECTED_USDC_REDEEMED, "mint recipient fail");
        uint strategyUSDCAfter = USDC.balanceOf(address(strategy));
        assertTrue(strategyUSDCAfter == strategyUSDCBefore - EXPECTED_USDC_REDEEMED, "strategy usdc deposit failed");
        uint reportedStrategyUSDCAfter = strategy.totalHoldings();
        assertTrue(strategyUSDCAfter == reportedStrategyUSDCAfter, "strategy usdc reporting failed");
        uint totalSupplyAfter = YUSD.totalSupply();
        assertTrue(totalSupplyAfter == totalSupplyBefore - EXPECTED_YUSD_BURNED, "total supply fail");
        uint yusdHolderYUSDAfter = YUSD.balanceOf(YUSD_HOLDER);
        assertTrue(yusdHolderYUSDAfter == yusdHolderYUSDBefore - REDEEM_AMOUNT_YUSD, "usdc holder balance didn't decrease");
        uint YUSDContractDebt = psm.YUSDContractDebt();
        // uint EXPECTED_TOTAL_CONTRACT_DEBT_AFTER_REDEEM = 1000e18 * 99 / 100 - 98e18; stack too deep
        // Original mint amount - redeem amount, in USDC
        assertTrue(YUSDContractDebt == 1000e18 * 99 / 100 - 98e18, "Contract debt doesn't line up");
    }


    // YUSD Debt limit + redeem to bring it under limit test
    function testRedeemYUSDDebtLimit() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Set new limit to 1900
        vm.startPrank(treasury);
        psm.setDebtLimit(1900e18);
        vm.stopPrank();

        // Redeem for 500, should be allowed
        uint REDEEM_AMOUNT_YUSD = 500e18;
        vm.startPrank(YUSD_HOLDER);
        YUSD.approve(address(psm), MAX_UINT);
        psm.redeemYUSD(REDEEM_AMOUNT_YUSD, MINT_RECIPIENT);
        vm.stopPrank();

        // Mint again for 1000
        vm.startPrank(USDC_HOLDER);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Set debt limit to below current amount
        vm.startPrank(treasury);
        psm.setDebtLimit(10e18);
        vm.stopPrank();

        // Still allowed to redeem even though debt limit has been reached
        vm.startPrank(YUSD_HOLDER);
        psm.redeemYUSD(REDEEM_AMOUNT_YUSD, MINT_RECIPIENT);
        vm.stopPrank();
    }


    // Redeem over limit test, more than the amount that the contract has in debt
    function testRedeemOverLimit() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Attempt to redeem 1001, should fail since it is burning more than the contract
        // has ever minted
        uint REDEEM_AMOUNT_YUSD = 1001e18;
        vm.startPrank(YUSD_HOLDER);
        YUSD.approve(address(psm), MAX_UINT);
        vm.expectRevert("Burning more than the contract has in debt");
        psm.redeemYUSD(REDEEM_AMOUNT_YUSD, MINT_RECIPIENT);
    }


    // Redeeming to bring it under the debt limit allows another mint to happen. 
    function testRedeemDebtLimitChange() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Set new limit to 1900
        vm.startPrank(treasury);
        psm.setDebtLimit(1900e18);
        vm.stopPrank();

        // Try again for 1000
        vm.startPrank(USDC_HOLDER);
        vm.expectRevert("Cannot mint more than PSM Debt limit");
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        // Redeem 500 to bring it under the total
        uint REDEEM_AMOUNT_YUSD = 500e18;
        vm.startPrank(YUSD_HOLDER);
        YUSD.approve(address(psm), MAX_UINT);
        psm.redeemYUSD(REDEEM_AMOUNT_YUSD, MINT_RECIPIENT);
        vm.stopPrank();

        // Mint again for 1000, should go through
        vm.startPrank(USDC_HOLDER);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
    }

    // Test redeem paused
    function testRedeemPaused() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        vm.startPrank(treasury);
        psm.toggleRedeemPaused(true);
        vm.stopPrank();

        // Attempt to redeem 500, should fail since it is paused
        uint REDEEM_AMOUNT_YUSD = 500e18;
        vm.startPrank(YUSD_HOLDER);
        YUSD.approve(address(psm), MAX_UINT);
        vm.expectRevert("Redeem paused");
        psm.redeemYUSD(REDEEM_AMOUNT_YUSD, MINT_RECIPIENT);
    }


    /// ===========================================
    /// Strategy tests
    /// ===========================================


    // new strategy test 
    // Set a new strategy, and it should move the USDC over to the new strategy, and 
    // approve the new strategy so it is usable in the same way
    function testStrategyUpgrade() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        uint holdingsBefore = strategy.totalHoldings();

        // Set new strategy to a different strategy address
        TestStrategyDummy newStrategy = new TestStrategyDummy();
        vm.startPrank(treasury);
        newStrategy.initialize(address(psm));
        psm.setStrategy(address(newStrategy));
        vm.stopPrank();
        
        // Make sure that new strategy holds the correct amount of USDC since it should
        // have all been withdrawn to the new contract. 
        uint holdingsAfter = newStrategy.totalHoldings();
        assertTrue(holdingsBefore == holdingsAfter);

        uint oldStrategyHoldingsAfter = strategy.totalHoldings();
        assertTrue(oldStrategyHoldingsAfter == 0);

        // Mint again in PSM, should send it correctly to the new strategy
        vm.startPrank(USDC_HOLDER);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        uint holdingsAfter2 = newStrategy.totalHoldings();
        uint EXPECTED_MINT_AMOUNT_POST_FEE = MINT_AMOUNT_USDC * 99 / 100;
        assertTrue(holdingsAfter + EXPECTED_MINT_AMOUNT_POST_FEE == holdingsAfter2);   
    }


    // new strategy test
    // Should not be able to set to new strategy not initialized or wrong psm address initialized
    function testStrategyUpgradeInitializeOwner() public {
        // Set new strategy to a different strategy address
        TestStrategyDummy newStrategy = new TestStrategyDummy();
        vm.startPrank(treasury);
        // not initialized
        vm.expectRevert("Not initialized or wrong owner of strategy");
        psm.setStrategy(address(newStrategy));

        // Initialized wrong owner address
        newStrategy.initialize(address(1));
        vm.expectRevert("Not initialized or wrong owner of strategy");
        psm.setStrategy(address(newStrategy));
    }


    // harvest test 
    // With the strategy, if there is a greater amount of USDC in the strategy after some period 
    // of time from yield or some strategy, the harvest should mint the amount of YUSD necessary
    // to balance it with the PSM. 
    function testStrategyHarvest() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        uint EXPECTED_MINT_AMOUNT_POST_FEE = MINT_AMOUNT_USDC * 99 / 100;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);

        // Add some USDC to the strategy, as if it made some yield. 
        uint YIELD_AMOUNT = 50e6;
        USDC.transfer(address(strategy), YIELD_AMOUNT);
        vm.stopPrank();

        // assert that the total holdings are correct 
        uint totalHoldings = strategy.totalHoldings();
        assertTrue(totalHoldings == EXPECTED_MINT_AMOUNT_POST_FEE + YIELD_AMOUNT);

        // Execute harvest
        uint contractDebtBefore = psm.YUSDContractDebt();
        uint feeRecipientBefore = YUSD.balanceOf(FEE_RECIPIENT);

        psm.harvest();

        uint contractDebtAfter = psm.YUSDContractDebt();
        uint feeRecipientAfter = YUSD.balanceOf(FEE_RECIPIENT);
        uint YIELD_AMOUNT_IN_YUSD = YIELD_AMOUNT * 1e12;

        // Harvest amount should equal discrepancy in debt
        assertTrue(contractDebtBefore + YIELD_AMOUNT_IN_YUSD == contractDebtAfter);
        // And fee recipient should receive it 
        assertTrue(feeRecipientBefore + YIELD_AMOUNT_IN_YUSD == feeRecipientAfter);
    }


    // harvest test can not go over the debt limit
    function testStrategyHarvestOverDebtLimit() public {
        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        uint EXPECTED_MINT_AMOUNT_POST_FEE = MINT_AMOUNT_USDC * 99 / 100;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);

        // Add some USDC to the strategy, as if it made some yield. 
        uint YIELD_AMOUNT = 50e6;
        USDC.transfer(address(strategy), YIELD_AMOUNT);
        vm.stopPrank();

        // assert that the total holdings are correct 
        uint totalHoldings = strategy.totalHoldings();
        assertTrue(totalHoldings == EXPECTED_MINT_AMOUNT_POST_FEE + YIELD_AMOUNT);

        // Set new limit to 0
        vm.startPrank(treasury);
        psm.setDebtLimit(0);
        vm.stopPrank();

        // Execute harvest, should revert 
        vm.expectRevert("Cannot mint more than PSM Debt limit");
        psm.harvest();
    }

    /// ===========================================
    /// aUSDC PSM Strategy test
    /// ===========================================
    function testRealStrategyDeposit() public {
        // Deploy new strategy and deploy
        aUSDCPSMStrategy newStrategy = new aUSDCPSMStrategy(address(psm));

        vm.startPrank(treasury);
        psm.setStrategy(address(newStrategy));
        vm.stopPrank();


        // From USDC holder, mint in PSM
        uint MINT_AMOUNT_USDC = 1000e6;
        uint EXPECTED_MINT_AMOUNT_POST_FEE = MINT_AMOUNT_USDC * 99 / 100;
        vm.startPrank(USDC_HOLDER);
        USDC.approve(address(psm), MAX_UINT);
        psm.mintYUSD(MINT_AMOUNT_USDC, MINT_RECIPIENT);
        vm.stopPrank();

        uint totalHoldings = newStrategy.totalHoldings();
        assertTrue(totalHoldings <= 990e6+1e4);
        assertTrue(totalHoldings >= 990e6-1e4);

        vm.startPrank(MINT_RECIPIENT);
        YUSD.approve(address(psm), MAX_UINT);
        uint256 amountRedeemed = psm.redeemYUSD(100e18, MINT_RECIPIENT);
        assertTrue(amountRedeemed <= 99e6+1e4);
        assertTrue(amountRedeemed >= 99e6-1e4);
        vm.stopPrank();

        address YetiVaultaUSDCHolder = 0xAAAaaAaaAaDd4AA719f0CF8889298D13dC819A15;
        vm.startPrank(YetiVaultaUSDCHolder);
        IERC20 vaultToken = IERC20(0xAD69de0CE8aB50B729d3f798d7bC9ac7b4e79267);
        vaultToken.transfer(address(newStrategy), 50e18);        
        vm.stopPrank();

        // Execute harvest
        uint contractDebtBefore = psm.YUSDContractDebt();
        uint feeRecipientBefore = YUSD.balanceOf(FEE_RECIPIENT);

        psm.harvest();

        uint contractDebtAfter = psm.YUSDContractDebt();
        uint feeRecipientAfter = YUSD.balanceOf(FEE_RECIPIENT);
        uint YIELD_AMOUNT_IN_YUSD = 50e18 * IYetiVaultToken(0xAD69de0CE8aB50B729d3f798d7bC9ac7b4e79267).underlyingPerReceipt() * 1e12 / 1e18;

        // Harvest amount should equal discrepancy in debt
        assertTrue(contractDebtBefore + YIELD_AMOUNT_IN_YUSD <= contractDebtAfter + 1e16);
        assertTrue(contractDebtBefore + YIELD_AMOUNT_IN_YUSD >= contractDebtAfter - 1e16);
        // And fee recipient should receive it 
        assertTrue(feeRecipientBefore + YIELD_AMOUNT_IN_YUSD <= feeRecipientAfter + 1e16);
        assertTrue(feeRecipientBefore + YIELD_AMOUNT_IN_YUSD >= feeRecipientAfter - 1e16);
        

    }


    /// ===========================================
    /// Admin function tests
    /// ===========================================


    // Strategy owner is PSM test 
    // Functions deposit() and withdraw() should revert if not called by the PSM
    function testOwnerStrategy() public {
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.deposit(1e6);

        vm.expectRevert("Ownable: caller is not the owner");
        strategy.withdraw(1e6);
    } 


    // Owner test
    // Functions setFee, setDebtLimit, setFeeRecipient, setStrategy should be only owner
    function testOwnerPSM() public {
        vm.expectRevert("Ownable: caller is not the owner");
        psm.setFee(1);

        vm.expectRevert("Ownable: caller is not the owner");
        psm.setDebtLimit(1);

        vm.expectRevert("Ownable: caller is not the owner");
        psm.setFeeRecipient(FEE_RECIPIENT);

        vm.expectRevert("Ownable: caller is not the owner");
        psm.setStrategy(FEE_RECIPIENT);

        vm.expectRevert("Ownable: caller is not the owner");
        psm.toggleRedeemPaused(true);
    }

}
