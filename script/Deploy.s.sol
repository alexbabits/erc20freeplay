// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC20FreePlay} from "../src/ERC20FreePlay.sol";
import {Escrow} from "../src/Escrow.sol";
import {Loot} from "../src/Loot.sol";
import {Exchange} from "../src/Exchange.sol";

contract Deploy is Script {

    function run() public {
        vm.startBroadcast();

        uint256 initialSupply = 1e27; 
        address owner = msg.sender;
        uint64 subscriptionId = 9745; // chainlink subscription ID
        address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; // VRF Sepolia coordinator address
        Escrow escrow = new Escrow(owner);
        Loot loot = new Loot(owner);
        ERC20FreePlay erc20FreePlay = new ERC20FreePlay(owner, subscriptionId, vrfCoordinator, initialSupply, address(escrow), address(loot));

        /**
         * Note: When deploing a FP token that is a derivative of an already existing token (fpDAI) for example
         * you must deploy with it the `Exchange.sol` contract, which will allow for wrapping/unwrapping.
         * For any other case where the FP token is not associated with an already existing token, no need to deploy Exchange.sol.
         * In this example, we are using LINK as the `normal token` and fpLINK as our ERC20FreePlay token.
        */
        address chainlinkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // LINK sepolia address
        Exchange exchange = new Exchange(chainlinkToken, address(erc20FreePlay));

        console.log("Deployed Escrow.sol at address: ", address(escrow));
        console.log("Deployed Loot.sol at address: ", address(loot));
        console.log("Deployed ERC20FreePlay.sol at address: ", address(erc20FreePlay));
        console.log("Deployed Exchange.sol at address: ", address(exchange));

        /**
         * Note: Call post-deployment setters to set and associate addresses properly.
         * This had to be done because we had a circular references between the contracts. Each contract needed eachothers addresses.
         */
        escrow.setFreePlayTokenAddress(address(erc20FreePlay));
        escrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(erc20FreePlay));
        escrow.renounceOwnership(); // This should work? Ownership no longer needed for escrow after deployment and addressess are set.

        vm.stopBroadcast();
    }
}