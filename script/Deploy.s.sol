// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC20FreePlay} from "../src/ERC20FreePlay.sol";
import {Escrow} from "../src/Escrow.sol";
import {Loot} from "../src/Loot.sol";

contract Deploy is Script {

    function run() public {
        vm.startBroadcast();

        uint256 initialSupply = 1e27; 
        address owner = msg.sender;
        uint64 subscriptionId = 9745; // chainlink subscription ID
        uint256 keeperFee = 100; // 1%
        uint256 penaltyFee = 5000; // 50%
        // Deploy contracts
        Escrow escrow = new Escrow(owner);
        Loot loot = new Loot(owner);
        ERC20FreePlay erc20freePlay = new ERC20FreePlay(owner, subscriptionId, initialSupply, address(escrow), address(loot), keeperFee, penaltyFee);
        console.log("Deployed Escrow.sol at address: ", address(escrow));
        console.log("Deployed Loot.sol at address: ", address(loot));
        console.log("Deployed ERC20FreePlay.sol at address: ", address(erc20freePlay));

        /**
         * Call post-deployment setters to set and associate addresses properly.
         * This had to be done because we had a circular references between the contracts. Each contract needed eachothers addresses.
         */
        escrow.setFreePlayTokenAddress(address(erc20freePlay));
        escrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(erc20freePlay));

        vm.stopBroadcast();
    }
}