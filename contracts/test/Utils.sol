// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

library Utils {
    function assertSmallDiff(uint a, uint b, uint diff) public pure returns (bool){
        if (a < b) { 
            if ((1e18*a)/b > 1e18+diff) {
                return false;
            }
        } else {
            if ((1e18*b)/a > 1e18+diff) {
                return false;
            }
        }
        return true;
    }

    function assertSmallDiff(uint a, uint b) public pure returns (bool) {
        return assertSmallDiff(a, b, 1e5);
    }
}