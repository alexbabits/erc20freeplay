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

        // Constructor args
        address owner = msg.sender;
        uint256 initialSupply = 1e27; 
        uint64 subscriptionId = 9745; // chainlink subscription ID
        bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // VRF gas lane option, Sepolia only has this one
        uint32 callbackGasLimit = 40000; // VRF gas limit for `fulfillRandomWords()` callback execution.
        uint16 requestConfirmations = 3; // VRF number of block confirmations to prevent re-orgs.
        address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; // VRF Sepolia coordinator address

        // function constructorPartTwo args
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

        Escrow escrow = new Escrow(owner);
        Loot loot = new Loot(owner);
        ERC20FreePlay erc20FreePlay = new ERC20FreePlay(
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
         * Note: Must immediately call this during deployment script to properly finish constructing the contract
         * We had to split up the construction in 2 phases because "Stack Too Deep" error occured when
         * trying to pass in and use too many args in the constructor.
         */
        erc20FreePlay.constructorPartTwo(keeperReward, penaltyFee, maxTimelockPeriod, maxExpirationPeriod, requiredDonationAmounts, failureThresholds);
        
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
         * This had to be done because we have circular references between the contracts. Each contract needed eachothers addresses.
         */
        escrow.setFreePlayTokenAddress(address(erc20FreePlay));
        escrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(erc20FreePlay));
        escrow.renounceOwnership(); // Ownership no longer needed for escrow after deployment and addressess are set.

        vm.stopBroadcast();
    }
}