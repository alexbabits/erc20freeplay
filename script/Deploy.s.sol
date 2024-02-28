// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockFreePlayToken} from "../src/MockFreePlayToken.sol";
import {MockEscrow} from "../src/MockEscrow.sol";
import {Loot} from "../src/Loot.sol";

contract Deploy is Script {

    function run() public {
        vm.startBroadcast();

        uint256 initialSupply = 1e27; 
        address initialOwner = msg.sender;

        // Deploy contracts
        MockEscrow mockEscrow = new MockEscrow(initialOwner);
        Loot loot = new Loot(initialOwner);
        MockFreePlayToken mockFreePlayToken = new MockFreePlayToken(initialSupply, address(mockEscrow), address(loot));
        console.log("Deployed MockEscrow.sol at address: ", address(mockEscrow));
        console.log("Deployed Loot.sol at address: ", address(loot));
        console.log("Deployed MockFreePlayToken.sol at address: ", address(mockFreePlayToken));

        /**
         * Call post-deployment setters to set and associate addresses properly.
         * This had to be done because we had a circular references between the contracts. Each contract needed eachothers addresses.
         */
        mockEscrow.setFreePlayTokenAddress(address(mockFreePlayToken));
        mockEscrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(mockFreePlayToken));

        vm.stopBroadcast();
    }
}