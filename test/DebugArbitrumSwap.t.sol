// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenSwapper.sol";
import "../src/interfaces/ISwapper.sol";

contract DebugArbitrumSwap is Test {
    TokenSwapper swapper;
    address constant SWAPPER_ADDR = 0xD12200745Fbb85f37F439DC81F5a649FF131C675;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant XAUT = 0x40461291347e1eCbb09499F3371D3f17f10d7159;
    address constant USER = 0x2Bda11F04b8F96D361D2DBB1bA8c36B744B4b42A;

    function setUp() public {
        vm.createSelectFork("https://arbitrum-mainnet.infura.io/v3/136ed41a59fd4cb2990353e603345171");
        swapper = TokenSwapper(SWAPPER_ADDR);
    }

    function testSwapUsdtToXaut() public {
        uint256 amountIn = 30000; // 3 USDT (6 decimals)
        
        // Impersonate USDT holder or deal tokens
        deal(USDT, USER, amountIn);
        
        vm.startPrank(USER);
        IERC20(USDT).approve(address(swapper), amountIn);
        
        console.log("Attempting swap...");
        try swapper.swap(USDT, XAUT, amountIn, 0, USER) returns (uint256 amountOut) {
            console.log("Swap successful! AmountOut:", amountOut);
        } catch Error(string memory reason) {
            console.log("Swap failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Swap failed with low-level error");
            console.logBytes(lowLevelData);
        }
        vm.stopPrank();
    }
}
