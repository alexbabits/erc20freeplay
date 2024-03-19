// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {EnumsEventsErrors} from "../src/EnumsEventsErrors.sol";
import {FPToken} from "../src/FPToken.sol";
import {Escrow} from "../src/Escrow.sol";
import {Loot} from "../src/Loot.sol";
import {Transmuter} from "../src/Transmuter.sol";
import {ERC20Mock} from "./ERC20Mock.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract FreePlayTokenTest is Test, EnumsEventsErrors {
    FPToken fpToken;
    Escrow escrow;
    Loot loot;
    Transmuter transmuter;
    ERC20Mock erc20Mock;
    VRFCoordinatorV2Mock coordinator;

    address Owner = address(0x420691337);
    address Alice = address(0xA11CE);
    address Bob = address(0xB0B);
    address Charlie = address(0xC);
    address ArbitraryYieldHandlingContract = address(0xFED);

    uint256 initialSupply = 1e27; // 1 billion initial supply, 1e18 * 1e9.
    uint96 baseFee = 1e17; // 0.1 base LINK fee
    uint96 gasPriceLink = 1e9; // gas price

    bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // VRF gas lane option, Sepolia only has this one
    uint32 callbackGasLimit = 40000; // VRF gas limit for `fulfillRandomWords()` callback execution.
    uint16 private requestConfirmations = 3; // VRF number of block confirmations to prevent re-orgs.
    uint256 _keeperReward = 100; // 1% (`_` preface just bc naming was the same with other test function declarations)
    uint256 penaltyFee = 5000; // 50%
    uint64 maxTimelockPeriod = 3650 days;
    uint64 maxExpirationPeriod = 3650 days;

    function setUp() public {
        // Deploy mock VRF coordinator, setup and fund subscription
        coordinator = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
        uint64 subscriptionId = coordinator.createSubscription();
        coordinator.fundSubscription(subscriptionId, 1_000_000e18);

        // Deploy consumer contract (fpToken) and other protocol contracts
        Owner = address(this);
        escrow = new Escrow(Owner);
        loot = new Loot(Owner);
        fpToken = new FPToken(
            Owner, 
            initialSupply,
            subscriptionId, 
            keyHash,
            callbackGasLimit,
            requestConfirmations,
            address(coordinator), 
            address(escrow), 
            address(loot)
        );

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

        // Call part two of construction (fixes stack too deep from too many constructor args).
        fpToken.constructorPartTwo(
            _keeperReward, 
            penaltyFee, 
            maxTimelockPeriod, 
            maxExpirationPeriod, 
            requiredDonationAmounts, 
            failureThresholds
        );

        // Deploy Mock ERC20 and transmuter for testing wrapping/unwrapping.
        erc20Mock = new ERC20Mock();
        transmuter = new Transmuter(address(erc20Mock), address(fpToken));

        // Setters needed to associate addresses with eachother.
        fpToken.setTransmuterAddress(address(transmuter));
        loot.setFreePlayTokenAddress(address(fpToken));
        escrow.setFreePlayTokenAddress(address(fpToken));
        // We can renounce ownership of escrow immediately.
        escrow.renounceOwnership();
        
        // Add our free play token contract as the VRF consumooooor
        coordinator.addConsumer(subscriptionId, address(fpToken));
    }

    function test_deployment() public {
        assertEq(fpToken.keeperReward(), _keeperReward, "should be set correctly upon deployment...");
        assertEq(fpToken.penaltyFee(), penaltyFee, "...");
        assertEq(fpToken.keyHash(), keyHash, "...");
        assertEq(fpToken.callbackGasLimit(), callbackGasLimit, "...");
        assertEq(fpToken.requestConfirmations(), requestConfirmations, "...");
        assertEq(fpToken.subscriptionId(), 1, "..."); // Sub Id is just 1 in mock VRF
        assertEq(fpToken.maxTimelockPeriod(), maxTimelockPeriod, "...");
        assertEq(fpToken.maxExpirationPeriod(), maxExpirationPeriod, "...");
        assertEq(fpToken.escrow(), address(escrow), "...");
        assertEq(fpToken.loot(), address(loot), "...");
        assertEq(fpToken.transmuter(), address(transmuter), "should be set properly, Note: only for when FPToken is wrapper type");
        assertEq(fpToken.totalSupply(), initialSupply, "can mint total supply if FPToken is standalone");
        assertEq(fpToken.balanceOf(Owner), initialSupply, "Owner should have all tokens initially");

        // judge me idc
        (uint256 requiredDonationAmount0, uint16 failureThreshold0) = fpToken.getGlobalTierInfo(Tier(0));
        (uint256 requiredDonationAmount1, uint16 failureThreshold1) = fpToken.getGlobalTierInfo(Tier(1));
        (uint256 requiredDonationAmount2, uint16 failureThreshold2) = fpToken.getGlobalTierInfo(Tier(2));
        (uint256 requiredDonationAmount3, uint16 failureThreshold3) = fpToken.getGlobalTierInfo(Tier(3));
        (uint256 requiredDonationAmount4, uint16 failureThreshold4) = fpToken.getGlobalTierInfo(Tier(4));
        (uint256 requiredDonationAmount5, uint16 failureThreshold5) = fpToken.getGlobalTierInfo(Tier(5));

        assertEq(requiredDonationAmount0, 0, "Tier.One matches");
        assertEq(requiredDonationAmount1, 50e18, "Tier.Two matches");
        assertEq(requiredDonationAmount2, 200e18, "Tier.Three matches");
        assertEq(requiredDonationAmount3, 500e18, "Tier.Four matches");
        assertEq(requiredDonationAmount4, 1000e18, "Tier.Five matches");
        assertEq(requiredDonationAmount5, 5000e18, "Tier.Six matches");

        assertEq(failureThreshold0, 9500, "Tier.One matches");
        assertEq(failureThreshold1, 9800, "Tier.Two matches");
        assertEq(failureThreshold2, 9900, "Tier.Three matches");
        assertEq(failureThreshold3, 9950, "Tier.Four matches");
        assertEq(failureThreshold4, 9980, "Tier.Five matches");
        assertEq(failureThreshold5, 9990, "Tier.Six matches");

        // Cannot set dependent addresses more than once (should be set during deployment)
        vm.expectRevert();
        escrow.setFreePlayTokenAddress(address(0x123));
        vm.expectRevert();
        loot.setFreePlayTokenAddress(address(0x456));
        vm.expectRevert();
        fpToken.setTransmuterAddress(address(789));
    }

    function test_cannotCallConstructorPartTwoAfterDeployment() public {
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

        vm.expectRevert();
        fpToken.constructorPartTwo(
            _keeperReward, 
            penaltyFee, 
            maxTimelockPeriod, 
            maxExpirationPeriod, 
            requiredDonationAmounts, 
            failureThresholds
        );
    }

    function test_transfer_free_play_off() public {
        uint256 amountOne = 500e18; 
        uint256 amountTwo = 200e18;

        fpToken.transfer(Alice, amountOne); // Using ERC20 `transfer()`, NOT a native chain gas token `transfer()`.
        assertEq(fpToken.balanceOf(Alice), amountOne, "Alice should have 500 tokens");

        vm.prank(Alice);
        fpToken.transfer(Bob, amountTwo);
        assertEq(fpToken.balanceOf(Owner), initialSupply - amountOne, "Owner should have remaining tokens");
        assertEq(fpToken.balanceOf(Bob), amountTwo, "Bob should have 200 tokens");
        assertEq(fpToken.balanceOf(Alice), amountOne - amountTwo, "Alice should have 300 tokens");
    }

    function test_transferFrom_free_play_off() public {
        uint256 amount = 500e18;
        fpToken.approve(Alice, amount);
        vm.prank(Alice);
        fpToken.transferFrom(Owner, Bob, amount);
        assertEq(fpToken.balanceOf(Owner), initialSupply - amount, "Owner should have remaining tokens");
        assertEq(fpToken.balanceOf(Bob), amount, "Bob should have 500 tokens");
    }

    function test_mint_free_play_off() public {
        uint256 amount = 500e18;
        vm.startPrank(Owner);

        uint256 totalSupplyBefore = fpToken.totalSupply();
        fpToken.typicalMint(Alice, amount);
        uint256 totalSupplyAfter = fpToken.totalSupply();

        assertEq(fpToken.balanceOf(Alice), amount, "should have 500 tokens");
        assertEq(totalSupplyAfter, totalSupplyBefore + amount, "supply should have increased");
        vm.stopPrank();
    }

    function test_mint_free_play_on() public {
        uint256 amount = 500e18;

        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();

        vm.startPrank(Owner);

        uint256 totalSupplyBefore = fpToken.totalSupply();
        fpToken.typicalMint(Alice, amount);
        uint256 totalSupplyAfter = fpToken.totalSupply();

        assertEq(fpToken.balanceOf(Alice), 0, "should have 0 tokens");
        assertEq(fpToken.balanceOf(address(escrow)), amount, "should have 500 tokens");
        assertEq(totalSupplyAfter, totalSupplyBefore + amount, "supply should have increased");
        assertLt(totalSupplyBefore, totalSupplyAfter, "supply should increase, mints goes to Escrow");
        (uint256 credits,,,,,,,,,) = fpToken.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(credits, amount, "Alice should be credited 100 free play");
        vm.stopPrank();
    }

    function test_toggleFreePlayStatus() public {
        vm.startPrank(Alice);
        
        (,,,,State freePlayStatus,) = fpToken.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.UNINITIALIZED), "Initial state should be UNINITIALIZED");

        fpToken.toggleFreePlayStatus();
        (,,,,freePlayStatus,) = fpToken.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.ON), "State should be ON after first toggle");

        fpToken.toggleFreePlayStatus();
        (,,,,freePlayStatus,) = fpToken.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.OFF), "State should be OFF after second toggle");

        fpToken.toggleFreePlayStatus();
        (,,,,freePlayStatus,) = fpToken.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.ON), "State should be ON after third toggle");

        vm.stopPrank();
    }

    function test_setters() public {
        vm.startPrank(Owner);

        fpToken.setCallbackGasLimit(420000);
        fpToken.setRequestConfirmations(69); 
        fpToken.setSubscriptionId(9696);

        vm.expectRevert();
        fpToken.setCallbackGasLimit(2_500_001); // Must be [40k, 2.5M] inclusive
        vm.expectRevert();
        fpToken.setCallbackGasLimit(39999); // Must be [40k, 2.5M] inclusive

        vm.expectRevert();
        fpToken.setRequestConfirmations(2); // Must be [3, 200] inclusive
        vm.expectRevert();
        fpToken.setRequestConfirmations(201); // Must be [3, 200] inclusive
        
        vm.stopPrank();
    }

    function test_transfer_free_play_on() public {
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, 100e18); 

        assertEq(fpToken.balanceOf(Alice), 0, "Alice should have 0 tokens");
        assertEq(fpToken.balanceOf(address(escrow)), 100e18, "Escrow should have the 100 tokens");

        (uint256 credits, 
        uint256 requestId, 
        address owner, 
        uint64 requestedAt,
        uint64 unlocksAt, 
        uint64 expiresAt, 
        uint16 customFailureThreshold, 
        uint16 randomWord, 
        State claimStatus, 
        Tier claimTier) = fpToken.getFreePlayPosition(1); // First Position ID is 1.

        assertEq(credits, 100e18, "Position should be marked with the credits");
        assertEq(requestId, 0, "VRF request ID should not exist yet");
        assertEq(owner, Alice, "owner should be alice");
        assertEq(requestedAt, 0, "No request time yet bc position was only created, not claimed");
        assertEq(unlocksAt, block.timestamp, "should default to immediate unlock");
        assertEq(expiresAt, type(uint64).max, "should default to never expire");
        assertEq(customFailureThreshold, 0, "should have no custom failure threshold yet");
        assertEq(randomWord, 0, "should have no random word yet");
        assertEq(uint(claimStatus), uint(State.UNINITIALIZED), "should be integer 0");
        assertEq(uint(claimTier), uint(Tier.ONE), "should be integer 0");
    }

    function test_donate() public {
        uint256 amount = 20000e18;
        uint256 donationOne = 50e18;
        uint256 donationTwo = 20e18;
        uint256 donationThree = 8000e18;

        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // 20k real

        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();

        vm.startPrank(Owner);
        fpToken.transfer(Alice, amount); // 20k FP
        (,,,,,,,,,Tier claimTier) = fpToken.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should be tier ONE");
        vm.stopPrank();

        vm.startPrank(Alice);
        fpToken.approve(address(fpToken), amount); // approve full amount for all donations
        fpToken.donate(donationOne);
        assertEq(fpToken.balanceOf(Alice), amount - donationOne, "After donation Alice should have 19950 tokens left");
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should STILL be tier ONE after donation");
        (uint256 totalFreePlayCredits, uint256 amountDonated,,,,Tier tier) = fpToken.getUserInfo(Alice);
        assertEq(totalFreePlayCredits, amount, "Alice should have 20k FP credits after 1st position created");
        assertEq(amountDonated, donationOne, "Alice should have 50 donated tokens marked after 1st donation");
        assertEq(uint(tier), uint(Tier.TWO), "Alices UserInfo should have increased to Tier 2 after 1st donation");
        // Alice's Current State: 20k FP, 19950 Real, 50 Donated, Position 1 claimTier is Tier ONE. UserInfo tier is Tier TWO.

        // Purpose: If donation doesn't reach a threshold, it still gets recorded but Tier remains the same.
        fpToken.donate(donationTwo);
        assertEq(fpToken.balanceOf(Alice), amount - donationOne - donationTwo, "After donation Alice should have 19930 tokens left");
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should STILL be tier ONE after all donations");
        (,amountDonated,,,,tier) = fpToken.getUserInfo(Alice);
        assertEq(amountDonated, donationTwo + donationOne, "Alice should have 70 donated tokens marked after 2nd donation");
        assertEq(uint(tier), uint(Tier.TWO), "Alices UserInfo should STILL be Tier 2 after 2nd donation");
        // Alice's Current State: 20k FP, 19930 Real, 70 Donated, Position 1 claimTier is Tier ONE. UserInfo tier is Tier TWO.

        // Purpose: Alice can donate beyond max Tier amount, but then cannot donate again once already max tier.
        fpToken.donate(donationThree);
        assertEq(fpToken.balanceOf(Alice), amount - donationOne - donationTwo - donationThree, "11930 tokens left");
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should STILL be tier ONE after all donations");
        (,amountDonated,,,,tier) = fpToken.getUserInfo(Alice);
        assertEq(amountDonated, donationOne + donationTwo + donationThree, "Alice should have 8070 donated tokens marked after donations");
        assertEq(uint(tier), uint(Tier.SIX), "Alices UserInfo should be Tier 6 after 3rd donation");
        vm.expectRevert();
        fpToken.donate(1e18); // Cannot donate after max tier achieved
        vm.stopPrank();
        // Alice's Current State: 20k FP, 11930 Real, 8070 Donated, Position 1 claimTier is Tier ONE. UserInfo tier is Tier SIX.

        vm.startPrank(Owner);
        fpToken.transfer(Alice, amount); // 20k FP
        (,,,,,,,,,claimTier) = fpToken.getFreePlayPosition(2); // Alice's next FP Position is ID 2.
        assertEq(uint(claimTier), uint(Tier.SIX), "Alices next position should be Tier.SIX");
        vm.stopPrank();

        assertEq(fpToken.balanceOf(address(loot)), donationOne + donationTwo + donationThree, "Loot should have got all donations");
    }

    function test_setTimeLock() public {
        uint256 amount = 200e18;
        uint64 timeLockPeriod = 100 days;
        uint64 anotherPeriod = 200 days;
        uint64 longTimeLock = 3651 days;

        // Create FP Position before setting a time lock.
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // 1st FP Position
        (,,,,uint64 unlocksAt,,,,,) = fpToken.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(unlocksAt, block.timestamp, "Position is immediately unlocked and ready to be claimed");
        
        // Set a timelock and create another position.
        vm.prank(Alice);
        fpToken.setTimelock(timeLockPeriod);
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // 2nd FP Position
        (,,,,unlocksAt,,,,,) = fpToken.getFreePlayPosition(2); // Alice's position ID is 2.
        assertEq(unlocksAt, uint64(block.timestamp) + timeLockPeriod, "Position unlocks after the timelock period set");
        
        // Changing UserInfo "global" timelock doesn't effect unlock time of positions created in the past.
        vm.prank(Alice);
        fpToken.setTimelock(anotherPeriod);
        (,,,,uint64 unlocksAt1,,,,,) = fpToken.getFreePlayPosition(1); 
        assertEq(unlocksAt1, uint64(block.timestamp), "Position 1 should still unlock immediately");
        (,,,,uint64 unlocksAt2,,,,,) = fpToken.getFreePlayPosition(2);
        assertEq(unlocksAt2, uint64(block.timestamp) + timeLockPeriod, "Position 2 should still unlock after original time period set");

        // Cannot make timelock more than 10 years.
        vm.prank(Alice);
        vm.expectRevert();
        fpToken.setTimelock(longTimeLock);
    }

    function test_setExpiration() public {
        uint256 amount = 200e18;
        uint64 timeLockPeriod = 50 days;
        uint64 expirationPeriod = 100 days;
        uint64 anotherPeriod = 200 days;
        uint64 longExpiration = 3651 days;

        // Create FP Position before setting any timelock or expiration
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // 1st FP Position
        (,,,,,uint64 expiresAt,,,,) = fpToken.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(expiresAt, type(uint64).max, "Positions without expiration set do not expire.");

        // If timelock isn't set, expiration is just added to timestamp.
        vm.prank(Alice);
        fpToken.setExpiration(expirationPeriod);
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // 2nd FP Position
        (,,,,,expiresAt,,,,) = fpToken.getFreePlayPosition(2); // Alice's position ID is 2.
        assertEq(expiresAt, uint64(block.timestamp) + expirationPeriod, "Position expires after expiration period set");

        // If a timelock is also set, then expiration is after timelock and expiration period set.
        // The expiration timer starts ticking only AFTER the timelock is finished.
        vm.prank(Alice);
        fpToken.setTimelock(timeLockPeriod);
        fpToken.setExpiration(expirationPeriod);
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // 3rd FP Position
        (,,,,,expiresAt,,,,) = fpToken.getFreePlayPosition(3); // Alice's position ID is 3.
        assertEq(expiresAt, uint64(block.timestamp) + expirationPeriod + timeLockPeriod, "Position only expires after both");

        // Changing UserInfo "global" expiration period doesn't effect expiartion time of positions created in the past.
        vm.prank(Alice);
        fpToken.setExpiration(anotherPeriod);
        (,,,,,uint64 expiresAt1,,,,) = fpToken.getFreePlayPosition(1); 
        assertEq(expiresAt1, type(uint64).max, "Position 1 still never expires");
        (,,,,,uint64 expiresAt2,,,,) = fpToken.getFreePlayPosition(2);
        assertEq(expiresAt2, uint64(block.timestamp) + expirationPeriod, "Position 2 still expires at it's set time");
        (,,,,,uint64 expiresAt3,,,,) = fpToken.getFreePlayPosition(3);
        assertEq(expiresAt3, uint64(block.timestamp) + expirationPeriod + timeLockPeriod, "Position 3 still expires at it's set time");

        // Cannot make an expiration more than 10 years.
        vm.prank(Alice);
        vm.expectRevert();
        fpToken.setExpiration(longExpiration);
    }

    function test_emergencyUnlock() public {
        uint256 amount = 200e18;
        uint64 timeLockPeriod = 100 days;
        uint64 expirationPeriod = 200 days;
        
        // Create FP position with a timelock and expiration.
        vm.startPrank(Alice);
        fpToken.toggleFreePlayStatus();
        fpToken.setTimelock(timeLockPeriod);
        fpToken.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // 1st FP Position

        // Cannot initially claim the unmatured position.
        vm.startPrank(Alice);
        vm.expectRevert();
        fpToken.initiateClaim(1);

        // emergency unlock the position so we can claim it.
        fpToken.emergencyUnlock(1); // Alice's Position ID is 1.
        (uint256 credits,,,,uint64 unlocksAt,uint64 expiresAt,,,,) = fpToken.getFreePlayPosition(1);
        assertEq(credits, amount / 2, "FP credits should be slashed by the penalty fee of 50%");
        assertEq(unlocksAt, block.timestamp, "Position should now be immediately unlocked");
        assertEq(expiresAt, type(uint64).max, "For simplicity, emergency unlocked positions will not expire");
        assertEq(fpToken.balanceOf(address(loot)), amount / 2, "Loot immediately receives penalty amount underlying tokens");
        (uint256 totalFreePlayCredits,,,,,) = fpToken.getUserInfo(Alice);
        assertEq(totalFreePlayCredits, amount / 2, "Alice total tracked FP credits must also go down");

        // Cannot emergency unlock the FP position that has already been emergency unlocked.
        vm.expectRevert();
        fpToken.emergencyUnlock(1);
        vm.stopPrank();

        // Can now immediately claim the position since it's now unlocked. (Claims for only penalty amount though!)
        vm.startPrank(Alice);
        fpToken.initiateClaim(1);
        (,uint256 requestId,,,,,,,,) = fpToken.getFreePlayPosition(1);
        coordinator.fulfillRandomWords(requestId, address(fpToken)); // 1st rng is always 6462 in mocks, which is success
        fpToken.finalizeClaim(1, false);
        assertEq(fpToken.balanceOf(Alice), amount / 2, "Alice should only get 100 underlying tokens");
        vm.stopPrank();

        // Cannot emergency unlock FP Position that has status CLAIM_IN_PROGRESS.
        vm.prank(Bob);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Bob, amount); // position ID 2 for Bob

        vm.startPrank(Bob);
        fpToken.initiateClaim(2); // CLAIM_IN_PROGRESS status now
        vm.expectRevert();
        fpToken.emergencyUnlock(2);
        vm.stopPrank();

        // Cannot emergency unlock FP position that is already matured past its timelock.
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // position ID 3 for Alice
        vm.startPrank(Alice);
        vm.warp(timeLockPeriod + 1); // Position matured.
        vm.expectRevert();
        fpToken.emergencyUnlock(3); // Alice's Position ID is 3.
        vm.stopPrank();

        // Cannot emergency unlock FP position if you don't own it.
        vm.prank(Bob);
        vm.expectRevert();
        fpToken.emergencyUnlock(3); // Alice's position ID 3
    }   

    function test_decreaseFailureThreshold() public {
        uint256 amount = 200e18;
        uint16 _customFailureThreshold = 5000;
        uint256 keeperPct = 100;
        uint256 PCT_DENOMINATOR = 10000;
        uint256 keeperReward = amount * keeperPct / PCT_DENOMINATOR;
        uint256 lootReward = amount - keeperReward;

        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount);
        (,,,,,,uint16 customFailureThreshold,,,) = fpToken.getFreePlayPosition(1); // Alice Position ID is 1.
        assertEq(customFailureThreshold, 0, "customFailureThreshold for position should be 0");

        // All FP position's default to Tier.ONE which is 9500 failureThreshold (5% failure rate).
        vm.startPrank(Alice);
        fpToken.decreaseFailureThreshold(1, _customFailureThreshold); // new failure rate for position
        (,,,,,,customFailureThreshold,,,) = fpToken.getFreePlayPosition(1);
        assertEq(customFailureThreshold, _customFailureThreshold, "customFailureThreshold for position should decrease");
        
        // Cannot decrease FP Position if claim is in progress
        vm.startPrank(Alice);
        fpToken.initiateClaim(1);
        vm.expectRevert();
        fpToken.decreaseFailureThreshold(1, 1337);

        // When setting customFailureThreshold, must always decrease, never stay the same or increase. 
        vm.expectRevert();
        fpToken.decreaseFailureThreshold(1, _customFailureThreshold);

        // Cannot make customFailureThreshold for a position 0, as this is the SPECIAL default value.
        vm.expectRevert();
        fpToken.decreaseFailureThreshold(1, 0);
        vm.stopPrank();

        // If owner doesn't match to position, cannot change it.
        vm.prank(Bob);
        vm.expectRevert();
        fpToken.decreaseFailureThreshold(1, 1337);

        // Claiming a position with custom failure rate changes the failure rate during claim.
        vm.prank(Bob);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Bob, amount);
        vm.startPrank(Bob);
        fpToken.decreaseFailureThreshold(2, 420); // 4.2% success rate, decreased to show it effects claims
        fpToken.initiateClaim(2); // Bob's Position ID is 2
        // 2nd rng is 922 in mocks, which is failure because our custom failure threshold is now 420 instead of 9500 default.
        // 922 > 420 = failure!
        (,uint256 requestId,,,,,,,,) = fpToken.getFreePlayPosition(2); 
        coordinator.fulfillRandomWords(requestId, address(fpToken));
        // Should be failure, underlying tokens get sent to Loot.sol and keeper (Bob) instead of all to Bob.
        fpToken.finalizeClaim(2, false);  
        assertEq(fpToken.balanceOf(Bob), keeperReward, "Bob was the keeper here, got the 1% fee");
        assertEq(fpToken.balanceOf(address(loot)), lootReward, "Loot gets rest of position");
        vm.stopPrank();
    }

    function test_cleanUpExpiredPosition() public {
        uint256 amount = 200e18;
        uint64 expirationPeriod = 100 days;
        uint256 keeperReward = 100; // 1%

        // Prep user info for FP position
        vm.startPrank(Alice);
        fpToken.toggleFreePlayStatus();
        fpToken.setExpiration(expirationPeriod);
        vm.stopPrank();

        // Create FP Position
        vm.prank(Owner);
        fpToken.transfer(Alice, amount);
        (,,,,,uint64 expiresAt,,,,) = fpToken.getFreePlayPosition(1); // First Position ID is 1.
        assertEq(expiresAt, block.timestamp + expirationPeriod, "Position expires at current time + expirationPeriod");

        // Cannot clean up non-expired position
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + expirationPeriod); // 1 second before expiration
        vm.expectRevert();
        fpToken.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        vm.warp(uint64(block.timestamp) - expirationPeriod); // Reset time
        vm.stopPrank();

        // Clean up expired position
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + expirationPeriod + 1);
        fpToken.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        
        assertEq(fpToken.balanceOf(Alice), amount * keeperReward / 10000, "should be right reward");
        assertEq(fpToken.balanceOf(address(loot)), amount - (amount * keeperReward / 10000), "should be right reward");
        (uint256 totalFreePlayCredits,,,,,) = fpToken.getUserInfo(Alice);
        assertEq(totalFreePlayCredits, 0, "All free play credits removed");

        // Position should no longer exist.
        (uint256 credits, 
        uint256 requestId, 
        address owner, 
        uint64 requestedAt,
        uint64 unlocksAt, 
        uint64 expiresAt1, 
        uint16 customFailureThreshold, 
        uint16 randomWord, 
        State claimStatus, 
        Tier claimTier) = fpToken.getFreePlayPosition(1); 

        assertEq(credits, 0, "Position should have no credits");
        assertEq(requestId, 0, "VRF request ID should not exist");
        assertEq(owner, address(0), "owner should be nobody");
        assertEq(requestedAt, 0, "should be default value");
        assertEq(unlocksAt, 0, "should be default value");
        assertEq(expiresAt1, 0, "should be default value");
        assertEq(customFailureThreshold, 0, "should be default value");
        assertEq(randomWord, 0, "should be default value");
        assertEq(uint(claimStatus), uint(State.UNINITIALIZED), "should be integer 0");
        assertEq(uint(claimTier), uint(Tier.ONE), "should be integer 0");
        vm.stopPrank(); 
    }

    function test_cleanUpExpiredPositionReverts() public {
        // NOTE: Stack was too deep in `test_cleanUpExpiredPosition`, have to put last revert case here
        uint256 amount = 200e18;
        uint64 expirationPeriod = 69 days;

        // Prep user info for FP position
        vm.startPrank(Alice);
        fpToken.toggleFreePlayStatus();
        fpToken.setExpiration(expirationPeriod);
        vm.stopPrank();

        // Create FP Position
        vm.prank(Owner);
        fpToken.transfer(Alice, amount);
        (,,,,,uint64 expiresAt,,,,) = fpToken.getFreePlayPosition(1); // First Position ID is 1.
        assertEq(expiresAt, block.timestamp + expirationPeriod, "Position expires at current time + expirationPeriod");

        // Initiate claim
        vm.startPrank(Alice);
        fpToken.initiateClaim(1);

        // Warp until it's expired
        vm.warp(block.timestamp + expirationPeriod + 69);
        vm.expectRevert();
        // Position is expired but cannot clean up because claim in progress.
        fpToken.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        vm.stopPrank();
    }

    function test_lootWithdrawals() public {
        uint256 amount = 200e18;
        uint64 expirationPeriod = 100 days;
        uint256 keeperReward = 100; // 1%

        // Prep and create FP Position
        vm.startPrank(Alice);
        fpToken.toggleFreePlayStatus();
        fpToken.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount);

        // Expired position gets cleaned up
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + expirationPeriod + 1);
        fpToken.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        assertEq(fpToken.balanceOf(Alice), amount * keeperReward / 10000, "should be right reward");
        assertEq(fpToken.balanceOf(address(loot)), amount - (amount * keeperReward / 10000), "should be right reward");
        vm.stopPrank();

        // Non-owner cannot claim
        vm.startPrank(Bob);
        vm.expectRevert();
        loot.withdrawSpecificAmount(10e18, Bob);
        vm.expectRevert();
        loot.withdrawAll(Bob);
        vm.stopPrank();

        vm.startPrank(Owner);
        loot.withdrawSpecificAmount(69e18, Bob);
        assertEq(fpToken.balanceOf(Bob), 69e18, "Bob should get the loot");
        loot.withdrawAll(Bob);
        assertEq(fpToken.balanceOf(Bob), amount - (amount * keeperReward / 10000), "Bob should get the rest");
        vm.stopPrank();
    }

    function test_initiateClaim_fulfillRandomWords() public {
        uint256 amount = 200e18;

        // Create FP position
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // First FP Position ID is 1.
        (,uint256 requestId,,uint64 requestedAt,,,,uint16 randomWord, State claimStatus,) = fpToken.getFreePlayPosition(1); // First Position ID is 1.
        assertEq(requestId, 0, "VRF request ID should not exist yet");
        assertEq(randomWord, 0, "should have no random word yet");
        assertEq(uint(claimStatus), uint(State.UNINITIALIZED), "should be integer 0");
        assertEq(requestedAt, 0, "Should have no requestedAt time yet");

        // Initiate claim and fulfill the random word for this position.
        vm.startPrank(Alice);
        fpToken.initiateClaim(1); 

        (,
        uint256 requestIdForClaim
        ,,
        uint64 requestedAtForClaim
        ,,,,
        uint16 randomWordForClaim, 
        State claimStatusForClaim,) = fpToken.getFreePlayPosition(1); 

        assertEq(requestIdForClaim, 1, "VRF request ID should now exist"); // Note: For non-mock VRF, requestID is a hash, NOT a counter!
        assertEq(randomWordForClaim, 0, "should still have no random word yet until fulfillRandomWords() is called");
        assertEq(uint(claimStatusForClaim), uint(State.CLAIM_IN_PROGRESS), "claim should now be in progress for position");
        assertEq(requestedAtForClaim, uint64(block.timestamp), "should be requested at this timestamp");
        
        // Mock the callback giving the position the random word back.
        coordinator.fulfillRandomWords(requestIdForClaim, address(fpToken)); 
        (,,,,,,,uint16 randomWord1,,) = fpToken.getFreePlayPosition(1); 
        assertNotEq(randomWord1, randomWordForClaim, "random word now exists and will never be 0"); // [1, 10000] inclusive
        console.log("Random word generated for 1st position: ", randomWord1);
        vm.stopPrank(); 

        // Create another FP position and generate another random word (sanity check).
        vm.prank(Owner);
        fpToken.transfer(Alice, amount);
        vm.startPrank(Alice);
        fpToken.initiateClaim(2); // 2nd position for Alice
        (,uint256 requestId2,,,,,,,,) = fpToken.getFreePlayPosition(2); 
        coordinator.fulfillRandomWords(requestId2, address(fpToken)); 
        (,,,,,,,uint16 randomWord2,,) = fpToken.getFreePlayPosition(2); 
        console.log("Random word generated for 2nd position: ", randomWord2);
        vm.stopPrank();
    }

    function test_initiateClaimReverts() public {
        uint256 amount = 200e18;
        uint64 timeLockPeriod = 100 days;
        uint64 expirationPeriod = 200 days;
        uint256 keeperRewardPct = 100;
        uint256 PCT_DENOMINATOR = 10000;
        uint256 keeperReward = amount * keeperRewardPct / PCT_DENOMINATOR;
        uint256 lootReward = amount - keeperReward;

        vm.startPrank(Alice);
        fpToken.toggleFreePlayStatus();
        fpToken.setTimelock(timeLockPeriod);
        fpToken.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // Alice FP Position ID is 1.

        // Position not matured
        vm.prank(Alice);
        vm.expectRevert(); 
        fpToken.initiateClaim(1); 

        // Position matured but Position.owner != msg.sender
        vm.warp(uint64(block.timestamp) + timeLockPeriod + 1);
        vm.prank(Bob);
        vm.expectRevert();
        fpToken.initiateClaim(1);

        // Position status cannot be CLAIM_IN_PROGRESS (multiple VRF requests successfully denied per position).
        vm.startPrank(Alice);
        fpToken.initiateClaim(1); // initiate claim goes through
        vm.expectRevert();
        fpToken.initiateClaim(1); // reverts

        // Position gets immediately cleaned up if it's expired and a claim is attempted
        vm.startPrank(Bob);
        fpToken.toggleFreePlayStatus();
        fpToken.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        fpToken.transfer(Bob, amount); // Bob FP Position ID is 2.

        // Warp to expiration. Position automatically cleaned up
        vm.warp(block.timestamp + expirationPeriod + 1);
        vm.prank(Bob);
        fpToken.initiateClaim(2);
        assertEq(fpToken.balanceOf(Bob), keeperReward, "Bob gets keeper reward");
        assertEq(fpToken.balanceOf(address(loot)), lootReward, "Loot gets rest");
    }

    function test_finalizeClaim() public {
        uint256 amount = 200e18;
        uint256 keeperRewardPct = 100;
        uint256 PCT_DENOMINATOR = 10000;
        uint256 keeperReward = amount * keeperRewardPct / PCT_DENOMINATOR;
        uint256 lootReward = amount - keeperReward;
        // Create FP position
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); // First FP Position ID is 1.

        // Initiate claim, fulfillRandomWords, then finalize claim.
        // Should give Alice underlying tokens because RNG was success.
        vm.startPrank(Alice);
        fpToken.initiateClaim(1); 
        (,uint256 requestIdAlice,,,,,,,,) = fpToken.getFreePlayPosition(1); 
        coordinator.fulfillRandomWords(requestIdAlice, address(fpToken)); 
        (,,,,,,,uint16 randomWordAlice,,) = fpToken.getFreePlayPosition(1); 
        console.log("Random word generated for Alice's position: ", randomWordAlice);
        fpToken.finalizeClaim(1, false); // Keeper is Alice, it can also be anyone else.
        assertEq(fpToken.balanceOf(Alice), amount, "Alice should have received all underlying tokens");
        vm.stopPrank(); 

        // Failure claim result. `position.randomWord` must be > failureThreshold of tier.ONE of 9500 for example.
        vm.prank(Bob);
        fpToken.toggleFreePlayStatus();
        uint256 i = 2; // Starting position ID for Bob
        uint16 randomWordBob = 0;
        uint256 requestIdBob;

        // We loop through making positions and claiming until we get a failure.
        while(true) {
            vm.prank(Owner);
            fpToken.transfer(Bob, amount); 
            vm.startPrank(Bob);
            fpToken.initiateClaim(i);
            vm.stopPrank();
            (,requestIdBob,,,,,,,,) = fpToken.getFreePlayPosition(i); 
            coordinator.fulfillRandomWords(requestIdBob, address(fpToken)); 
            (,,,,,,,randomWordBob,,) = fpToken.getFreePlayPosition(i); 
            console.log("Random word generated for Bob's position: ", randomWordBob);
            if (randomWordBob > 9500) break;
            i++; 
        }

        vm.prank(Charlie); // Keeper can be anyone, A/B/C/Protocol/KeeperBot/etc.
        fpToken.finalizeClaim(i, false); 
        assertEq(fpToken.balanceOf(Bob), 0, "Bob should receive nothing, claim failed");
        assertEq(fpToken.balanceOf(Charlie), keeperReward, "Charlie the keeper gets the fee");
        assertEq(fpToken.balanceOf(address(loot)), lootReward, "Loot gets the rest");
        vm.prank(Owner);
        loot.withdrawAll(Charlie); // Owner withdraws all to Charlie
        assertEq(fpToken.balanceOf(Charlie), keeperReward + lootReward, "Lucky Charlie");
    }

    function test_finalizeClaimReverts() public {
        // Should revert if random word is 0 or claim status is NOT claim in progress
        uint256 amount = 200e18;

        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount);

        vm.startPrank(Alice);
        vm.expectRevert();
        fpToken.finalizeClaim(1, false); // revert, not CLAIM_IN_PROGRESS
        fpToken.initiateClaim(1); // Initiate the claim, request RNG
        vm.expectRevert();
        fpToken.finalizeClaim(1, false); // CLAIM_IN_PROGRESS but no random word yet
    }

    function test_initiateMultipleClaims() public {
        uint256 amount = 200e18;

        // Create FP positions
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.startPrank(Owner);
        fpToken.transfer(Alice, amount); // Alice FP Position ID 1
        fpToken.transfer(Alice, amount); // Alice FP Position ID 2
        fpToken.transfer(Alice, amount); // Alice FP Position ID 3
        vm.stopPrank();

        // Prep array of position IDs
        uint256[] memory positionIds = new uint256[](3);
        positionIds[0] = 1;
        positionIds[1] = 2;
        positionIds[2] = 3;

        // Initiate multiple claims
        vm.startPrank(Alice);
        fpToken.initiateMultipleClaims(positionIds); 
        vm.stopPrank();

        (,uint256 requestId1,,uint64 requestedAt1,,,,,State claimStatus1,) = fpToken.getFreePlayPosition(1); 
        (,uint256 requestId2,,uint64 requestedAt2,,,,,State claimStatus2,) = fpToken.getFreePlayPosition(2); 
        (,uint256 requestId3,,uint64 requestedAt3,,,,,State claimStatus3,) = fpToken.getFreePlayPosition(3); 

        assertEq(requestId1, 1, "VRF request ID should now exist"); // Note: For non-mock VRF, requestID is a hash, NOT a counter!
        assertEq(requestId2, 2, "..."); 
        assertEq(requestId3, 3, "...");

        assertEq(uint(claimStatus1), uint(State.CLAIM_IN_PROGRESS), "claim should now be in progress for position");
        assertEq(uint(claimStatus2), uint(State.CLAIM_IN_PROGRESS), "...");
        assertEq(uint(claimStatus3), uint(State.CLAIM_IN_PROGRESS), "...");

        assertEq(requestedAt1, uint64(block.timestamp), "should have current timestamp req at");
        assertEq(requestedAt2, uint64(block.timestamp), "...");
        assertEq(requestedAt3, uint64(block.timestamp), "...");
    }

    function test_finalizeMultipleClaims() public {
        uint256 amount = 200e18;

        // Create FP positions
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.startPrank(Owner);
        fpToken.transfer(Alice, amount); // Alice FP Position ID 1
        fpToken.transfer(Alice, amount); // Alice FP Position ID 2
        fpToken.transfer(Alice, amount); // Alice FP Position ID 3
        vm.stopPrank();

        // Prep array of position IDs
        uint256[] memory positionIds = new uint256[](3);
        positionIds[0] = 1;
        positionIds[1] = 2;
        positionIds[2] = 3;

        // Initiate multiple claims
        vm.prank(Alice);
        fpToken.initiateMultipleClaims(positionIds); 

        // requestId's are just 1, 2, 3. Coincidence that they correspond to position IDs.
        // Note: For non-mock VRF, requestID is a hash, NOT a counter!
        coordinator.fulfillRandomWords(1, address(fpToken)); // randomWord = 6462, result = success
        coordinator.fulfillRandomWords(2, address(fpToken)); // randomWord = 922, result = success
        coordinator.fulfillRandomWords(3, address(fpToken)); // randomWord = 5940, result = success

        vm.prank(Alice);
        fpToken.finalizeMultipleClaims(positionIds);
        assertEq(fpToken.balanceOf(Alice), amount*3, "winner winner winner chicken dinner");
    }

    function test_cleanUpMultipleExpiredPositions() public {
        uint256 amount = 200e18;
        uint64 expirationPeriod = 69 days;

        // Create FP positions
        vm.startPrank(Alice);
        fpToken.toggleFreePlayStatus();
        fpToken.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.startPrank(Owner);
        fpToken.transfer(Alice, amount); // Alice FP Position ID 1
        fpToken.transfer(Alice, amount); // Alice FP Position ID 2
        fpToken.transfer(Alice, amount); // Alice FP Position ID 3
        vm.stopPrank();

        console.logUint(block.timestamp);
        vm.warp(uint64(block.timestamp) + expirationPeriod + expirationPeriod + expirationPeriod);
        console.logUint(block.timestamp);

        // Prep array of position IDs
        uint256[] memory positionIds = new uint256[](3);
        positionIds[0] = 1;
        positionIds[1] = 2;
        positionIds[2] = 3;

        // Clean up expired positions
        vm.prank(Alice);
        fpToken.cleanUpMultipleExpiredPositions(positionIds); 
        assertEq(fpToken.balanceOf(Alice), 6e18, "gets keeper rewards"); // 1% * 600 = 6
        assertEq(fpToken.balanceOf(address(loot)), 594e18, "gets the rest");
    }

    // Wrapping normal tokens into FP tokens with FP status not ON serves no purpose btw. Only done for testing purposes.
    function test_wrapAndUnwrap_FP_OFF() public {
        console.log(address(transmuter));
        uint256 amount = 20e18;

        // Mint the normal token yield from staking to a handler contract first. (anyone can mint these mock tokens).
        erc20Mock.mint(ArbitraryYieldHandlingContract, amount);
        
        // approve the transmuter for wrapping and then wrap.
        vm.startPrank(ArbitraryYieldHandlingContract);
        erc20Mock.approve(address(transmuter), amount);
        transmuter.wrap(amount, Alice);

        assertEq(fpToken.balanceOf(Alice), amount, "Alice should have been forwarded the wrapped 20 FP tokens");
        assertEq(erc20Mock.balanceOf(address(transmuter)), amount, "transmuter should have the 20 normal tokens");
        assertEq(erc20Mock.balanceOf(ArbitraryYieldHandlingContract), 0, "Yield should have been forwarded to Alice via FP tokens");
        assertEq(fpToken.balanceOf(ArbitraryYieldHandlingContract), 0, "Yield should have been forwarded to Alice via FP tokens");
        assertEq(erc20Mock.balanceOf(Alice), 0, "Alice should have 0 normal tokens");
        vm.stopPrank();

        vm.startPrank(Alice);
        // Approve the transmuter for unwrapping FP tokens, then unwrap.
        fpToken.approve(address(transmuter), amount);
        transmuter.unwrap(amount);
        assertEq(erc20Mock.balanceOf(Alice), amount, "Alice should have 20 normal tokens now");
        assertEq(fpToken.balanceOf(Alice), 0, "Alice should have 0 FP tokens now");
        assertEq(erc20Mock.balanceOf(address(transmuter)), 0, "transmuter should have 0 normal tokens left");    
        assertEq(fpToken.balanceOf(address(transmuter)), 0, "transmuter should have 0 FP tokens");      
    }

    function test_wrapAndUnwrap_FP_ON() public {
        uint256 amount = 20e18;

        // Mint the normal token yield from staking to a handler contract first. (anyone can mint these mock tokens).
        erc20Mock.mint(ArbitraryYieldHandlingContract, amount);

        // Turn on Alice's FP status
        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();

        // approve the transmuter for wrapping and then wrap.
        vm.startPrank(ArbitraryYieldHandlingContract);
        erc20Mock.approve(address(transmuter), amount);
        transmuter.wrap(amount, Alice);

        assertEq(fpToken.balanceOf(Alice), 0, "Alice should have been 0 FP tokens");
        assertEq(erc20Mock.balanceOf(Alice), 0, "Alice should have 0 normal tokens");
        assertEq(erc20Mock.balanceOf(ArbitraryYieldHandlingContract), 0, "Yield should have been forwarded to Alice via FP tokens");
        assertEq(fpToken.balanceOf(ArbitraryYieldHandlingContract), 0, "Yield should have been forwarded to Alice via FP tokens");
        assertEq(erc20Mock.balanceOf(address(transmuter)), amount, "transmuter should have the 20 normal tokens");
        assertEq(fpToken.balanceOf(address(escrow)), amount, "Escrow should have the 20 FP tokens");
        (uint256 credits,,,,,,,,,) = fpToken.getFreePlayPosition(1); // First Position ID is 1.
        assertEq(credits, amount, "Alice should have instead gotten a position with 20 FP credits from the wrapping");
        vm.stopPrank();

        // Alice needs to claim her position first, and then unwrap tokens if they survive
        // (The RNG check while claiming is successful in tests because it's always 6462 for the first number generated)

        vm.startPrank(Alice);
        fpToken.initiateClaim(1); // Pos ID 1
        (,uint256 requestIdAlice,,,,,,,,) = fpToken.getFreePlayPosition(1); 
        coordinator.fulfillRandomWords(requestIdAlice, address(fpToken)); 
        (,,,,,,,uint16 randomWordAlice,,) = fpToken.getFreePlayPosition(1); 
        console.log("Random word generated for Alice's position: ", randomWordAlice);
        fpToken.finalizeClaim(1, false); // Keeper is Alice, it can also be anyone else.

        assertEq(fpToken.balanceOf(Alice), amount, "Alice should have received all underlying tokens");

        // She now has successfully gotten the underlying 20 FP tokens from her 20 FP credit position
        // And can now unwrap these FP tokens back for the normal tokens.
        // Approve the transmuter for unwrapping FP tokens, then unwrap.
        fpToken.approve(address(transmuter), amount);
        transmuter.unwrap(amount);
        assertEq(erc20Mock.balanceOf(Alice), amount, "Alice should have 20 normal tokens now");
        assertEq(fpToken.balanceOf(Alice), 0, "Alice should have 0 FP tokens now");
        assertEq(erc20Mock.balanceOf(address(transmuter)), 0, "transmuter should have 0 normal tokens left");    
        assertEq(fpToken.balanceOf(address(transmuter)), 0, "transmuter should have 0 FP tokens");  
        assertEq(fpToken.balanceOf(address(escrow)), 0, "Escrow should have 0 FP tokens"); 
        
        vm.stopPrank();
    }

    function test_fixFailedRequestPosition() public {
        uint256 amount = 200e18;

        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); 

        vm.startPrank(Alice);
        fpToken.initiateClaim(1); // First FP Position ID is 1.

        (,
        uint256 requestIdForClaim,
        ,
        uint64 requestedAtForClaim,
        ,,,
        uint16 randomWordForClaim,
        State claimStatusForClaim,
        ) = fpToken.getFreePlayPosition(1); 

        // Can't fix it yet since it was just made (need to be stuck for at least 26 hours).
        vm.expectRevert();
        fpToken.fixFailedRequestPosition(1);

        assertEq(requestIdForClaim, 1, "VRF request ID should now exist"); // Note: For non-mock VRF, requestID is a hash, NOT a counter!
        assertEq(randomWordForClaim, 0, "should still have no random word yet until fulfillRandomWords() is called");
        assertEq(uint(claimStatusForClaim), uint(State.CLAIM_IN_PROGRESS), "claim should now be in progress for position");
        assertEq(requestedAtForClaim, uint64(block.timestamp), "should be requested at this timestamp");

        // 26 hours forward to mock a failed request
        // We never call fulfillRandomWord() as to mimic one of three failures that can result in an stuck position
        // 1. Incorrect keyHash during request, 2. insufficient sub funds 3. fulfillRandomWords() itself reverts or low gas.
        vm.warp(block.timestamp + 93600); 
        fpToken.fixFailedRequestPosition(1); // pos ID is 1

        (,
        requestIdForClaim,
        ,
        requestedAtForClaim,
        ,,,
        randomWordForClaim, 
        claimStatusForClaim,) = fpToken.getFreePlayPosition(1); 
        
        assertEq(randomWordForClaim, 0, "Random word should still be 0"); 
        assertEq(uint(claimStatusForClaim), uint(State.UNINITIALIZED), "claim status should be reset to uninitialized");

        // Can now attempt claim again. The 2nd random word in tests is 922 which will result in success.
        fpToken.initiateClaim(1);
        (,uint256 requestId,,,,,,,,) = fpToken.getFreePlayPosition(1);
        coordinator.fulfillRandomWords(requestId, address(fpToken)); // 922 = randomWord
        fpToken.finalizeClaim(1, false);
        assertEq(fpToken.balanceOf(Alice), amount, "Alice should receive the underlying FP tokens");
        
        vm.stopPrank();
    }

    function test_fixFailedRequestPosition_Reverts() public {
        uint256 amount = 200e18;

        vm.prank(Alice);
        fpToken.toggleFreePlayStatus();
        vm.prank(Owner);
        fpToken.transfer(Alice, amount); 

        vm.startPrank(Alice);
        fpToken.initiateClaim(1); // First FP Position ID is 1.
        (,uint256 requestId,,,,,,,,) = fpToken.getFreePlayPosition(1);
        coordinator.fulfillRandomWords(requestId, address(fpToken));
        // Don't finalize claim, try to call the fix function but it fails.

        // Even though it's been over 26 hours, since we have a random word for the position, cannot "fix" it bc it's not broken.
        vm.expectRevert();
        fpToken.fixFailedRequestPosition(1);
        vm.warp(block.timestamp + 93600);
        vm.expectRevert();
        fpToken.fixFailedRequestPosition(1);

        vm.stopPrank();
    }
}