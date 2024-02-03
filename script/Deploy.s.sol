// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockDeferredToken} from "../src/MockDeferredToken.sol";

contract DeployMockDeferredToken is Script {

    function run() public {
        vm.startBroadcast();

        // Constructor Arguments
        uint256 initialSupply = 1e27; // 1 billion tokens with 18 decimals

        // Deploy contract
        MockDeferredToken mockDeferredToken = new MockDeferredToken(initialSupply);
        console.log("Deployed MockDeferredToken.sol at address:", address(mockDeferredToken));
        
        vm.stopBroadcast();
    }
}