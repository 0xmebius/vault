// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/Lever.sol";
import "./TestERC20.sol";
import "./Utils.sol";


// This test covers basic functionality of the Vault contract
// Basic withdraw and deposit functionality
// Basic token transfer/approval functionality
// Basic proportional distribution when new underlying tokens are minted to vault
// TODO: Test permit functions

contract TestLever is DSTest {

    uint constant MAX_INT = 2**256 - 1;
    uint constant ADMINFEE=100;
    uint constant CALLERFEE=10;
    uint constant MAX_REINVEST_STALE= 1 hours;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    IERC20 constant USDC = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664); //USDC
    IERC20 constant USDC_Native = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); //USDC Native
    address constant usdcHolder = 0xCe2CC46682E9C6D5f174aF598fb4931a9c0bE68e;
    address constant usdc_nativeHolder = 0x42d6Ce661bB2e5F5cc639E7BEFE74Ff9Fd649541;
    IERC20 constant WAVAX = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7); //WAVAX
    address constant wavaxHolder = 0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB; 

    address constant joePair = 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1; // USDC-WAVAX
    address constant joeRouter = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address constant aave = 0x4F01AeD16D97E3aB5ab2B501154DC9bb0F1A5A2C;
    address constant aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    Lever public lever;

    function setUp() public {
        lever = new Lever();
        lever.setJoeRouter(joeRouter);
        lever.setAAVE(aave, aaveV3);
        lever.setApprovals(address(WAVAX), joeRouter, MAX_INT);
        lever.setApprovals(address(USDC), joeRouter, MAX_INT);
        lever.setApprovals(address(WAVAX), aave, MAX_INT);
        lever.setApprovals(address(USDC), aave, MAX_INT);
        lever.setApprovals(joePair, joeRouter, MAX_INT);
        vm.startPrank(wavaxHolder);
        WAVAX.transfer(address(this), WAVAX.balanceOf(wavaxHolder));
        vm.stopPrank();
        vm.startPrank(usdcHolder);
        USDC.transfer(address(this), USDC.balanceOf(usdcHolder));
        vm.stopPrank();
        vm.startPrank(usdc_nativeHolder);
        USDC_Native.transfer(address(this), USDC_Native.balanceOf(usdc_nativeHolder) / 10000);
        vm.stopPrank();
    }

    function testVanillaJoeSwapFork() public {
        uint256 amtIn = 1e18;
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        lever.setRoute(address(WAVAX), address(USDC), _path);
        uint256 preA = WAVAX.balanceOf(address(this));
        uint256 preB = USDC.balanceOf(address(this));
        WAVAX.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(WAVAX), address(USDC), amtIn, 0);
        uint256 postA = WAVAX.balanceOf(address(this));
        uint256 postB = USDC.balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    function testVanillaJLPInFork() public {
        uint256 amtIn = 1e18;
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(joePair, 2, address(WAVAX), address(joePair), 0, 0, 0);
        lever.setRoute(address(WAVAX), address(joePair), _path);
        uint256 preA = WAVAX.balanceOf(address(this));
        uint256 preB = IERC20(joePair).balanceOf(address(this));
        WAVAX.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(WAVAX), joePair, amtIn, 0);
        uint256 postA = WAVAX.balanceOf(address(this));
        uint256 postB = IERC20(joePair).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    function testVanillaJLPInNOutFork() public {
        testVanillaJLPInFork();
        uint256 amtIn = IERC20(joePair).balanceOf(address(this));
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(joePair, 2, joePair, address(WAVAX), 0, 0, 0);
        lever.setRoute(address(joePair), address(WAVAX), _path);
        uint256 preB = WAVAX.balanceOf(address(this));
        uint256 preA = IERC20(joePair).balanceOf(address(this));
        IERC20(joePair).transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), joePair, address(WAVAX), amtIn, 0);
        uint256 postB = WAVAX.balanceOf(address(this));
        uint256 postA = IERC20(joePair).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }

    // 2 pool swap
    function testVanillaCRV1Fork() public {
        address crv = 0x3a43A5851A3e3E0e25A3c1089670269786be1577;
        address out = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
        uint256 amtIn = USDC.balanceOf(address(this));
        lever.setApprovals(address(USDC), crv, MAX_INT);
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(crv, 3, address(USDC), out, -2, 0, 1);
        lever.setRoute(address(USDC), out, _path);
        uint256 preA = USDC.balanceOf(address(this));
        uint256 preB = IERC20(out).balanceOf(address(this));
        USDC.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(USDC), out, amtIn, 0);
        uint256 postA = USDC.balanceOf(address(this));
        uint256 postB = IERC20(out).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    // 2 pool swap to lp
    function testVanillaCRV2Fork() public {
        address crv = 0x3a43A5851A3e3E0e25A3c1089670269786be1577;
        address out = 0x3a43A5851A3e3E0e25A3c1089670269786be1577;
        uint256 amtIn = USDC.balanceOf(address(this));
        lever.setApprovals(address(USDC), crv, MAX_INT);
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(crv, 3, address(USDC), out, -2, 0, -1);
        lever.setRoute(address(USDC), out, _path);
        uint256 preA = USDC.balanceOf(address(this));
        uint256 preB = IERC20(out).balanceOf(address(this));
        USDC.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(USDC), out, amtIn, 0);
        uint256 postA = USDC.balanceOf(address(this));
        uint256 postB = IERC20(out).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    // 2 pool swap to lp and back
    function testVanillaCRV3Fork() public {
        testVanillaCRV2Fork();
        address crv = 0x3a43A5851A3e3E0e25A3c1089670269786be1577;
        address _in = 0x3a43A5851A3e3E0e25A3c1089670269786be1577;
        uint256 amtIn = IERC20(_in).balanceOf(address(this));
        lever.setApprovals(_in, crv, MAX_INT);
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(crv, 3, _in, address(USDC), -2, -1, 0);
        lever.setRoute(_in, address(USDC), _path);
        uint256 preB = USDC.balanceOf(address(this));
        uint256 preA = IERC20(_in).balanceOf(address(this));
        IERC20(_in).transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), _in, address(USDC), amtIn, 0);
        uint256 postB = USDC.balanceOf(address(this));
        uint256 postA = IERC20(_in).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }

    // 2 pool (technically metapool) swap
    function testVanillaCRV4Fork() public {
        address crv = 0x30dF229cefa463e991e29D42DB0bae2e122B2AC7;
        address out = 0x130966628846BFd36ff31a822705796e8cb8C18D;
        uint256 amtIn = USDC.balanceOf(address(this));
        lever.setApprovals(address(USDC), crv, MAX_INT);
        lever.setApprovals(0x46A51127C3ce23fb7AB1DE06226147F446e4a857, crv, MAX_INT);
        Router.Node[] memory _path = new Router.Node[](2);
        _path[0] = Router.Node(address(0), 6, address(USDC), 0x46A51127C3ce23fb7AB1DE06226147F446e4a857, 0, 0, 0);
        _path[1] = Router.Node(crv, 3, 0x46A51127C3ce23fb7AB1DE06226147F446e4a857, out, 2, 2, 0);

        lever.setRoute(address(USDC), out, _path);
        uint256 preA = USDC.balanceOf(address(this));
        uint256 preB = IERC20(out).balanceOf(address(this));
        USDC.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(USDC), out, amtIn, 0);
        uint256 postA = USDC.balanceOf(address(this));
        uint256 postB = IERC20(out).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    // 2 pool (technically metapool) swap into lp through basepool
    function testVanillaCRV5Fork() public {
        address crv = 0x30dF229cefa463e991e29D42DB0bae2e122B2AC7;
        address out = 0x30dF229cefa463e991e29D42DB0bae2e122B2AC7;
        uint256 amtIn = USDC.balanceOf(address(this));
        lever.setApprovals(address(USDC), 0x7f90122BF0700F9E7e1F688fe926940E8839F353, MAX_INT);
        lever.setApprovals(0x46A51127C3ce23fb7AB1DE06226147F446e4a857, crv, MAX_INT);
        lever.setApprovals(0x1337BedC9D22ecbe766dF105c9623922A27963EC, crv, MAX_INT);
        Router.Node[] memory _path = new Router.Node[](2);
        // _path[0] = Router.Node(address(0), 6, address(USDC), 0x46A51127C3ce23fb7AB1DE06226147F446e4a857, 0, 0, 0);
        _path[0] = Router.Node(0x7f90122BF0700F9E7e1F688fe926940E8839F353, 3, address(USDC), 0x1337BedC9D22ecbe766dF105c9623922A27963EC, 3, 1, -1);
        _path[1] = Router.Node(crv, 3, 0x46A51127C3ce23fb7AB1DE06226147F446e4a857, out, -2, 1, -1);

        lever.setRoute(address(USDC), out, _path);
        uint256 preA = USDC.balanceOf(address(this));
        uint256 preB = IERC20(out).balanceOf(address(this));
        USDC.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(USDC), out, amtIn, 0);
        uint256 postA = USDC.balanceOf(address(this));
        uint256 postB = IERC20(out).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    
    function testVanillaAAVEInFork() public {
        address out = 0x46A51127C3ce23fb7AB1DE06226147F446e4a857;
        uint256 amtIn = USDC.balanceOf(address(this));
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(address(0), 6, address(USDC), out, 0, 0, 0);
        lever.setRoute(address(USDC), out, _path);
        uint256 preA = USDC.balanceOf(address(this));
        uint256 preB = IERC20(out).balanceOf(address(this));
        USDC.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(USDC), out, amtIn, 0);
        uint256 postA = USDC.balanceOf(address(this));
        uint256 postB = IERC20(out).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    function testVanillaAAVEInNOutFork() public {
        testVanillaAAVEInFork();
        address _in = 0x46A51127C3ce23fb7AB1DE06226147F446e4a857;
        uint256 amtIn = IERC20(_in).balanceOf(address(this));
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(_in, 6, _in, address(USDC), 0, 0, 0);
        lever.setRoute(_in, address(USDC), _path);
        uint256 preB = USDC.balanceOf(address(this));
        uint256 preA = IERC20(_in).balanceOf(address(this));
        IERC20(_in).transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), _in, address(USDC), amtIn, 0);
        uint256 postB = USDC.balanceOf(address(this));
        uint256 postA = IERC20(_in).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    function testVanillaCompInFork() public {
        address out = 0xBEb5d47A3f720Ec0a390d04b4d41ED7d9688bC7F;
        uint256 amtIn = USDC.balanceOf(address(this));
        lever.setApprovals(address(USDC), out, MAX_INT);
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(out, 7, address(USDC), out, 0, 0, 0);
        lever.setRoute(address(USDC), out, _path);
        uint256 preA = USDC.balanceOf(address(this));
        uint256 preB = IERC20(out).balanceOf(address(this));
        USDC.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(USDC), out, amtIn, 0);
        uint256 postA = USDC.balanceOf(address(this));
        uint256 postB = IERC20(out).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }
    function testVanillaCompInNOutFork() public {
        testVanillaCompInFork();
        address _in = 0xBEb5d47A3f720Ec0a390d04b4d41ED7d9688bC7F;
        uint256 amtIn = IERC20(_in).balanceOf(address(this));
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(_in, 7, _in, address(USDC), 0, 0, 0);
        lever.setRoute(_in, address(USDC), _path);
        uint256 preB = USDC.balanceOf(address(this));
        uint256 preA = IERC20(_in).balanceOf(address(this));
        IERC20(_in).transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), _in, address(USDC), amtIn, 0);
        uint256 postB = USDC.balanceOf(address(this));
        uint256 postA = IERC20(_in).balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }

    // Helper function to test a platypus swap through a specific pool
    function testPlatypusSwap(address pool, address _in, address _out) internal {
        IERC20 tokenIn = IERC20(_in);
        IERC20 tokenOut = IERC20(_out);
        uint256 amtIn = tokenIn.balanceOf(address(this));
        lever.setApprovals(address(tokenIn), pool, MAX_INT);
        Router.Node[] memory _path = new Router.Node[](1);
        _path[0] = Router.Node(pool, 9, address(tokenIn), _out, 0, 0, 0);
        lever.setRoute(address(tokenIn), _out, _path);

        // Perform swap
        uint256 preA = tokenIn.balanceOf(address(this));
        uint256 preB = tokenOut.balanceOf(address(this));
        tokenIn.transfer(address(lever), amtIn);
        uint amtOut = lever.unRoute(address(this), address(tokenIn), _out, amtIn, 0);
        uint256 postA = tokenIn.balanceOf(address(this));
        uint256 postB = tokenOut.balanceOf(address(this));
        assertTrue(postB-preB == amtOut);
        assertTrue(postB > preB);
        assertTrue(preA > postA);
    }

    // Swap USDC to YUSD through alt pool
    function testAltPoolPlatypusSwap() public {
        address platypusYUSDPool = 0xC828D995C686AaBA78A4aC89dfc8eC0Ff4C5be83;
        address _in = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E; // usdc native
        address _out = 0x111111111111ed1D73f860F57b2798b683f2d325; // yusd
        testPlatypusSwap(platypusYUSDPool, _in, _out);
    }

    // Swap USDC to USDt through main pool
    function testMainPoolPlatypusSwap() public {
        address platypusMainPool = 0x66357dCaCe80431aee0A7507e2E361B7e2402370;
        address _in = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E; // usdc native
        address _out = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7; // usdt native
        testPlatypusSwap(platypusMainPool, _in, _out);
    }
}
