// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {TransparentUpgradeableProxy} from "openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract VaultProxy is TransparentUpgradeableProxy {
    constructor(address _logic,
                address admin_,
                bytes memory _calldata)
                TransparentUpgradeableProxy(
                    _logic,
                    admin_,
                    _calldata) {}
}