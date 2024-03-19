// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {FPToken} from "../src/FPToken.sol";
import {Escrow} from "../src/Escrow.sol";
import {Loot} from "../src/Loot.sol";
import {Transmuter} from "../src/Transmuter.sol";

contract Deploy is Script {

    function run() public {
        vm.startBroadcast();

        // FP Token Constructor args
        address owner = msg.sender;
        uint256 initialSupply = 1e27; // 1e9 * 1e18 = 1,000,000,000 tokens with 18 decimals.
        uint64 subscriptionId = 9745; // chainlink subscription ID
        bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // VRF gas lane option, Sepolia only has this one
        uint32 callbackGasLimit = 40000; // VRF gas limit for `fulfillRandomWords()` callback execution.
        uint16 requestConfirmations = 3; // VRF number of block confirmations to prevent re-orgs.
        address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; // VRF Sepolia coordinator address

        // FP Token function `constructorPartTwo()` args
        uint256 keeperReward = 100; // 1%
        uint256 penaltyFee = 5000; // 50%
        uint64 maxTimelockPeriod = 3650 days;
        uint64 maxExpirationPeriod = 3650 days;
        uint256[] memory requiredDonationAmounts = new uint256[](6);
        requiredDonationAmounts[0] = 0;
        requiredDonationAmounts[1] = 50e18;
        requiredDonationAmounts[2] = 200e18;
        requiredDonationAmounts[3] = 500e18;
        requiredDonationAmounts[4] = 1000e18;
        requiredDonationAmounts[5] = 5000e18;
        uint16[] memory failureThresholds = new uint16[](6);
        failureThresholds[0] = 9500;
        failureThresholds[1] = 9800;
        failureThresholds[2] = 9900;
        failureThresholds[3] = 9950;
        failureThresholds[4] = 9980;
        failureThresholds[5] = 9990;

        // Deploy Escrow and Loot with reference to an owner. Needed for all types of FP tokens.
        Escrow escrow = new Escrow(owner);
        Loot loot = new Loot(owner);

        // Deploy FP Token
        FPToken fpToken = new FPToken(
            owner,
            initialSupply, 
            subscriptionId, 
            keyHash,
            callbackGasLimit,
            requestConfirmations,
            vrfCoordinator, 
            address(escrow), 
            address(loot)
        );

        /**
         * Note: Must always immediately call this to properly finish constructing/initializing the FP Token contract.
         * We had to split up the construction in 2 phases because "Stack Too Deep" error occured when
         * trying to pass in too many args in the constructor.
         */
        fpToken.constructorPartTwo(keeperReward, penaltyFee, maxTimelockPeriod, maxExpirationPeriod, requiredDonationAmounts, failureThresholds);
    
        // Note: Only deploy transmuter when making a "Wrapper" FP Token.
        address chainlinkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // LINK sepolia address
        Transmuter transmuter = new Transmuter(chainlinkToken, address(fpToken));

        // Note: The contracts circularly reference each other so we must call post-deployment setters to setup their addresses properly.
        // Note: DO NOT set a transmuter if FP token is meant to be "Standalone".
        // Note: Ownership is no longer needed for the escrow after its deployment AND the addressess are set.
        fpToken.setTransmuterAddress(address(transmuter)); 
        loot.setFreePlayTokenAddress(address(fpToken));
        escrow.setFreePlayTokenAddress(address(fpToken));
        escrow.renounceOwnership(); 

        console.log("Deployed FPToken.sol at address: ", address(fpToken));
        console.log("Deployed Escrow.sol at address: ", address(escrow));
        console.log("Deployed Loot.sol at address: ", address(loot));
        console.log("Deployed Transmuter.sol at address: ", address(transmuter)); // Not needed for standalone FP tokens.

        vm.stopBroadcast();
    }
}