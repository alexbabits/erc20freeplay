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

        Escrow escrow = new Escrow(owner);
        Loot loot = new Loot(owner);
        ERC20FreePlay erc20FreePlay = new ERC20FreePlay(owner, subscriptionId, initialSupply, address(escrow), address(loot));
        console.log("Deployed Escrow.sol at address: ", address(escrow));
        console.log("Deployed Loot.sol at address: ", address(loot));
        console.log("Deployed ERC20FreePlay.sol at address: ", address(erc20FreePlay));

        /**
         * Call post-deployment setters to set and associate addresses properly.
         * This had to be done because we had a circular references between the contracts. Each contract needed eachothers addresses.
         */
        escrow.setFreePlayTokenAddress(address(erc20FreePlay));
        escrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(erc20FreePlay));

        vm.stopBroadcast();
    }
}