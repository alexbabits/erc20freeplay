// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {ERC20FreePlay, EnumsEventsErrors} from "../src/ERC20FreePlay.sol";
import {Escrow} from "../src/Escrow.sol";
import {Loot} from "../src/Loot.sol";

import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

// 1. @audit TODO: With reverts, plug in the custom errors, make sure they match (meh)
// 2. @audit TODO: With events, make sure all events are emitted correctly (meh, just visually inspect closely)
// 3. @audit TODO: Should probably test front-end getters return the right amounts for tier/next tier too

contract FreePlayTokenTest is Test, EnumsEventsErrors {
    ERC20FreePlay erc20FreePlay;
    Escrow escrow;
    Loot loot;
    VRFCoordinatorV2Mock coordinator;

    address Owner;
    address Alice = address(0xA11CE);
    address Bob = address(0xB0B);
    address Charlie = address(0xC);

    uint256 initialSupply = 1e27; // 1 billion initial supply, 1e18 * 1e9.
    uint96 baseFee = 1e17; // 0.1 base LINK fee
    uint96 gasPriceLink = 1e9; // gas price

    function setUp() public {
        // Deploy mock VRF coordinator, setup and fund subscription
        coordinator = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
        uint64 subscriptionId = coordinator.createSubscription();
        coordinator.fundSubscription(subscriptionId, 1_000_000e18);

        // Deploy consumer contract (erc20freeplay) and other protocol contracts
        Owner = address(this);
        escrow = new Escrow(Owner);
        loot = new Loot(Owner);
        erc20FreePlay = new ERC20FreePlay(Owner, subscriptionId, address(coordinator), initialSupply, address(escrow), address(loot));
        escrow.setFreePlayTokenAddress(address(erc20FreePlay));
        escrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(erc20FreePlay));

        // Add the consumer
        coordinator.addConsumer(subscriptionId, address(erc20FreePlay));
    }

    function test_deployment() public {
        assertEq(erc20FreePlay.totalSupply(), initialSupply, "Incorrect total supply");
        assertEq(erc20FreePlay.balanceOf(Owner), initialSupply, "Owner should have all tokens initially");
    }

    function test_transfer_free_play_off() public {
        uint256 amountOne = 500e18; 
        uint256 amountTwo = 200e18;

        erc20FreePlay.transfer(Alice, amountOne); // Using ERC20 `transfer()`, NOT a native chain gas token `transfer()`.
        assertEq(erc20FreePlay.balanceOf(Alice), amountOne, "Alice should have 500 tokens");

        vm.prank(Alice);
        erc20FreePlay.transfer(Bob, amountTwo);
        assertEq(erc20FreePlay.balanceOf(Owner), initialSupply - amountOne, "Owner should have remaining tokens");
        assertEq(erc20FreePlay.balanceOf(Bob), amountTwo, "Bob should have 200 tokens");
        assertEq(erc20FreePlay.balanceOf(Alice), amountOne - amountTwo, "Alice should have 300 tokens");
    }

    function test_transferFrom_free_play_off() public {
        uint256 amount = 500e18;
        erc20FreePlay.approve(Alice, amount);
        vm.prank(Alice);
        erc20FreePlay.transferFrom(Owner, Bob, amount);
        assertEq(erc20FreePlay.balanceOf(Owner), initialSupply - amount, "Owner should have remaining tokens");
        assertEq(erc20FreePlay.balanceOf(Bob), amount, "Bob should have 500 tokens");
    }

    function test_mint_free_play_off() public {
        uint256 amount = 500e18;
        vm.startPrank(Owner);

        uint256 totalSupplyBefore = erc20FreePlay.totalSupply();
        erc20FreePlay.mint(Alice, amount);
        uint256 totalSupplyAfter = erc20FreePlay.totalSupply();

        assertEq(erc20FreePlay.balanceOf(Alice), amount, "should have 500 tokens");
        assertEq(totalSupplyAfter, totalSupplyBefore + amount, "supply should have increased");
        vm.stopPrank();
    }

    function test_toggleFreePlayStatus() public {
        vm.startPrank(Alice);
        
        (,,,,State freePlayStatus,) = erc20FreePlay.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.UNINITIALIZED), "Initial state should be UNINITIALIZED");

        erc20FreePlay.toggleFreePlayStatus();
        (,,,,freePlayStatus,) = erc20FreePlay.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.ON), "State should be ON after first toggle");

        erc20FreePlay.toggleFreePlayStatus();
        (,,,,freePlayStatus,) = erc20FreePlay.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.OFF), "State should be OFF after second toggle");

        erc20FreePlay.toggleFreePlayStatus();
        (,,,,freePlayStatus,) = erc20FreePlay.getUserInfo(Alice);
        assertEq(uint(freePlayStatus), uint(State.ON), "State should be ON after third toggle");

        vm.stopPrank();
    }

    function test_setters() public {
        vm.startPrank(Owner);

        erc20FreePlay.setKeeperReward(420);
        erc20FreePlay.setPenaltyFee(6969);
        erc20FreePlay.setCallbackGasLimit(420000);
        erc20FreePlay.setRequestConfirmations(69); 
        erc20FreePlay.setSubscriptionId(9696);

        vm.expectRevert();
        erc20FreePlay.setKeeperReward(10000); // Must be [0, 9999] inclusive
        
        vm.expectRevert();
        erc20FreePlay.setPenaltyFee(100001); // Must be [0, 10000] inclusive

        vm.expectRevert();
        erc20FreePlay.setCallbackGasLimit(2_500_001); // Must be LT 2.5M

        vm.expectRevert();
        erc20FreePlay.setRequestConfirmations(2); // Must be [3, 200] inclusive
        vm.expectRevert();
        erc20FreePlay.setRequestConfirmations(201); // Must be [3, 200] inclusive
        
        vm.stopPrank();
    }

    function test_transfer_free_play_on() public {
        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, 100e18); 
        assertEq(erc20FreePlay.balanceOf(Alice), 0, "Alice should have 0 tokens");
        assertEq(erc20FreePlay.balanceOf(address(escrow)), 100e18, "Escrow should have the 100 tokens");

        (uint256 credits, 
        uint256 requestId, 
        address owner, 
        uint64 unlocksAt, 
        uint64 expiresAt, 
        uint16 customFailureThreshold, 
        uint16 randomWord, 
        State claimStatus, 
        Tier claimTier) = erc20FreePlay.getFreePlayPosition(1); // First Position ID is 1.

        assertEq(credits, 100e18, "Position should be marked with the credits");
        assertEq(requestId, 0, "VRF request ID should not exist yet");
        assertEq(owner, Alice, "owner should be alice");
        assertEq(unlocksAt, block.timestamp, "should default to immediate unlock");
        assertEq(expiresAt, type(uint64).max, "should default to never expire");
        assertEq(customFailureThreshold, 0, "should have no custom failure threshold yet");
        assertEq(randomWord, 0, "should have no random word yet");
        assertEq(uint(claimStatus), uint(State.UNINITIALIZED), "should be integer 0");
        assertEq(uint(claimTier), uint(Tier.ONE), "should be integer 0");
    }

    function test_mint_free_play_on() public {
        uint256 amount = 500e18;

        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();

        vm.startPrank(Owner);

        uint256 totalSupplyBefore = erc20FreePlay.totalSupply();
        erc20FreePlay.mint(Alice, amount);
        uint256 totalSupplyAfter = erc20FreePlay.totalSupply();

        assertEq(erc20FreePlay.balanceOf(Alice), 0, "should have 0 tokens");
        assertEq(erc20FreePlay.balanceOf(address(escrow)), amount, "should have 500 tokens");
        assertEq(totalSupplyAfter, totalSupplyBefore + amount, "supply should have increased");
        assertLt(totalSupplyBefore, totalSupplyAfter, "supply should increase, mints goes to Escrow");
        (uint256 credits,,,,,,,,) = erc20FreePlay.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(credits, amount, "Alice should be credited 100 free play");
        vm.stopPrank();
    }

    function test_donate() public {
        uint256 amount = 20000e18;
        uint256 donationOne = 50e18;
        uint256 donationTwo = 20e18;
        uint256 donationThree = 8000e18;

        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 20k real

        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();

        vm.startPrank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 20k FP
        (,,,,,,,,Tier claimTier) = erc20FreePlay.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should be tier ONE");
        vm.stopPrank();

        vm.startPrank(Alice);
        erc20FreePlay.approve(address(erc20FreePlay), amount); // approve full amount for all donations
        erc20FreePlay.donate(donationOne);
        assertEq(erc20FreePlay.balanceOf(Alice), amount - donationOne, "After donation Alice should have 19950 tokens left");
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should STILL be tier ONE after donation");
        (uint256 totalFreePlayCredits, uint256 amountDonated,,,,Tier tier) = erc20FreePlay.getUserInfo(Alice);
        assertEq(totalFreePlayCredits, amount, "Alice should have 20k FP credits after 1st position created");
        assertEq(amountDonated, donationOne, "Alice should have 50 donated tokens marked after 1st donation");
        assertEq(uint(tier), uint(Tier.TWO), "Alices UserInfo should have increased to Tier 2 after 1st donation");
        // Alice's Current State: 20k FP, 19950 Real, 50 Donated, Position 1 claimTier is Tier ONE. UserInfo tier is Tier TWO.

        // Purpose: If donation doesn't reach a threshold, it still gets recorded but Tier remains the same.
        erc20FreePlay.donate(donationTwo);
        assertEq(erc20FreePlay.balanceOf(Alice), amount - donationOne - donationTwo, "After donation Alice should have 19930 tokens left");
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should STILL be tier ONE after all donations");
        (,amountDonated,,,,tier) = erc20FreePlay.getUserInfo(Alice);
        assertEq(amountDonated, donationTwo + donationOne, "Alice should have 70 donated tokens marked after 2nd donation");
        assertEq(uint(tier), uint(Tier.TWO), "Alices UserInfo should STILL be Tier 2 after 2nd donation");
        // Alice's Current State: 20k FP, 19930 Real, 70 Donated, Position 1 claimTier is Tier ONE. UserInfo tier is Tier TWO.

        // Purpose: Alice can donate beyond max Tier amount, but then cannot donate again once already max tier.
        erc20FreePlay.donate(donationThree);
        assertEq(erc20FreePlay.balanceOf(Alice), amount - donationOne - donationTwo - donationThree, "11930 tokens left");
        assertEq(uint(claimTier), uint(Tier.ONE), "Alices original position should STILL be tier ONE after all donations");
        (,amountDonated,,,,tier) = erc20FreePlay.getUserInfo(Alice);
        assertEq(amountDonated, donationOne + donationTwo + donationThree, "Alice should have 8070 donated tokens marked after donations");
        assertEq(uint(tier), uint(Tier.SIX), "Alices UserInfo should be Tier 6 after 3rd donation");
        vm.expectRevert();
        erc20FreePlay.donate(1e18); // Cannot donate after max tier achieved
        vm.stopPrank();
        // Alice's Current State: 20k FP, 11930 Real, 8070 Donated, Position 1 claimTier is Tier ONE. UserInfo tier is Tier SIX.

        vm.startPrank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 20k FP
        (,,,,,,,,claimTier) = erc20FreePlay.getFreePlayPosition(2); // Alice's next FP Position is ID 2.
        assertEq(uint(claimTier), uint(Tier.SIX), "Alices next position should be Tier.SIX");
        vm.stopPrank();

        assertEq(erc20FreePlay.balanceOf(address(loot)), donationOne + donationTwo + donationThree, "Loot should have got all donations");
    }

    function test_setTimeLock() public {
        uint256 amount = 200e18;
        uint64 timeLockPeriod = 100 days;
        uint64 anotherPeriod = 200 days;
        uint64 longTimeLock = 3651 days;

        // Create FP Position before setting a time lock.
        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 1st FP Position
        (,,,uint64 unlocksAt,,,,,) = erc20FreePlay.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(unlocksAt, block.timestamp, "Position is immediately unlocked and ready to be claimed");
        
        // Set a timelock and create another position.
        vm.prank(Alice);
        erc20FreePlay.setTimelock(timeLockPeriod);
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 2nd FP Position
        (,,,unlocksAt,,,,,) = erc20FreePlay.getFreePlayPosition(2); // Alice's position ID is 2.
        assertEq(unlocksAt, uint64(block.timestamp) + timeLockPeriod, "Position unlocks after the timelock period set");
        
        // Changing UserInfo "global" timelock doesn't effect unlock time of positions created in the past.
        vm.prank(Alice);
        erc20FreePlay.setTimelock(anotherPeriod);
        (,,,uint64 unlocksAt1,,,,,) = erc20FreePlay.getFreePlayPosition(1); 
        assertEq(unlocksAt1, uint64(block.timestamp), "Position 1 should still unlock immediately");
        (,,,uint64 unlocksAt2,,,,,) = erc20FreePlay.getFreePlayPosition(2);
        assertEq(unlocksAt2, uint64(block.timestamp) + timeLockPeriod, "Position 2 should still unlock after original time period set");

        // Cannot make timelock more than 10 years.
        vm.prank(Alice);
        vm.expectRevert();
        erc20FreePlay.setTimelock(longTimeLock);
    }

    function test_setExpiration() public {
        uint256 amount = 200e18;
        uint64 timeLockPeriod = 50 days;
        uint64 expirationPeriod = 100 days;
        uint64 anotherPeriod = 200 days;
        uint64 longExpiration = 3651 days;

        // Create FP Position before setting any timelock or expiration
        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 1st FP Position
        (,,,,uint64 expiresAt,,,,) = erc20FreePlay.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(expiresAt, type(uint64).max, "Positions without expiration set do not expire.");

        // If timelock isn't set, expiration is just added to timestamp.
        vm.prank(Alice);
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 2nd FP Position
        (,,,,expiresAt,,,,) = erc20FreePlay.getFreePlayPosition(2); // Alice's position ID is 2.
        assertEq(expiresAt, uint64(block.timestamp) + expirationPeriod, "Position expires after expiration period set");

        // If a timelock is also set, then expiration is after timelock and expiration period set.
        // The expiration timer starts ticking only AFTER the timelock is finished.
        vm.prank(Alice);
        erc20FreePlay.setTimelock(timeLockPeriod);
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 3rd FP Position
        (,,,,expiresAt,,,,) = erc20FreePlay.getFreePlayPosition(3); // Alice's position ID is 3.
        assertEq(expiresAt, uint64(block.timestamp) + expirationPeriod + timeLockPeriod, "Position only expires after both");

        // Changing UserInfo "global" expiration period doesn't effect expiartion time of positions created in the past.
        vm.prank(Alice);
        erc20FreePlay.setExpiration(anotherPeriod);
        (,,,,uint64 expiresAt1,,,,) = erc20FreePlay.getFreePlayPosition(1); 
        assertEq(expiresAt1, type(uint64).max, "Position 1 still never expires");
        (,,,,uint64 expiresAt2,,,,) = erc20FreePlay.getFreePlayPosition(2);
        assertEq(expiresAt2, uint64(block.timestamp) + expirationPeriod, "Position 2 still expires at it's set time");
        (,,,,uint64 expiresAt3,,,,) = erc20FreePlay.getFreePlayPosition(3);
        assertEq(expiresAt3, uint64(block.timestamp) + expirationPeriod + timeLockPeriod, "Position 3 still expires at it's set time");

        // Cannot make an expiration more than 10 years.
        vm.prank(Alice);
        vm.expectRevert();
        erc20FreePlay.setExpiration(longExpiration);
    }

    function test_emergencyUnlock() public {
        uint256 amount = 200e18;
        uint64 timeLockPeriod = 100 days;
        uint64 expirationPeriod = 200 days;
        
        // Create FP position with a timelock and expiration.
        vm.startPrank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        erc20FreePlay.setTimelock(timeLockPeriod);
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 1st FP Position

        // Cannot initially claim the unmatured position.
        vm.startPrank(Alice);
        vm.expectRevert();
        erc20FreePlay.initiateClaim(1);

        // emergency unlock the position so we can claim it.
        erc20FreePlay.emergencyUnlock(1); // Alice's Position ID is 1.
        (uint256 credits,,,uint64 unlocksAt,uint64 expiresAt,,,,) = erc20FreePlay.getFreePlayPosition(1);
        assertEq(credits, amount / 2, "FP credits should be slashed by the penalty fee of 50%");
        assertEq(unlocksAt, block.timestamp, "Position should now be immediately unlocked");
        assertEq(expiresAt, type(uint64).max, "For simplicity, emergency unlocked positions will not expire");
        assertEq(erc20FreePlay.balanceOf(address(loot)), amount / 2, "Loot immediately receives penalty amount underlying tokens");
        (uint256 totalFreePlayCredits,,,,,) = erc20FreePlay.getUserInfo(Alice);
        assertEq(totalFreePlayCredits, amount / 2, "Alice total tracked FP credits must also go down");

        // Cannot emergency unlock the FP position that has already been emergency unlocked.
        vm.expectRevert();
        erc20FreePlay.emergencyUnlock(1);
        vm.stopPrank();

        // Can now immediately claim the position since it's now unlocked. (Claims for only penalty amount though!)
        vm.startPrank(Alice);
        erc20FreePlay.initiateClaim(1);
        (,uint256 requestId,,,,,,,) = erc20FreePlay.getFreePlayPosition(1);
        coordinator.fulfillRandomWords(requestId, address(erc20FreePlay)); // 1st rng is always 6462 in mocks, which is success
        erc20FreePlay.finalizeClaim(1, false);
        assertEq(erc20FreePlay.balanceOf(Alice), amount / 2, "Alice should only get 100 underlying tokens");
        vm.stopPrank();

        // Cannot emergency unlock FP Position that has status CLAIM_IN_PROGRESS.
        vm.prank(Bob);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Bob, amount); // position ID 2 for Bob

        vm.startPrank(Bob);
        erc20FreePlay.initiateClaim(2); // CLAIM_IN_PROGRESS status now
        vm.expectRevert();
        erc20FreePlay.emergencyUnlock(2);
        vm.stopPrank();

        // Cannot emergency unlock FP position that is already matured past its timelock.
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // position ID 3 for Alice
        vm.startPrank(Alice);
        vm.warp(timeLockPeriod + 1); // Position matured.
        vm.expectRevert();
        erc20FreePlay.emergencyUnlock(3); // Alice's Position ID is 3.
        vm.stopPrank();

        // Cannot emergency unlock FP position if you don't own it.
        vm.prank(Bob);
        vm.expectRevert();
        erc20FreePlay.emergencyUnlock(3); // Alice's position ID 3
    }   

    function test_decreaseFailureThreshold() public {
        uint256 amount = 200e18;
        uint16 _customFailureThreshold = 5000;
        uint256 keeperPct = 100;
        uint256 PCT_DENOMINATOR = 10000;
        uint256 keeperReward = amount * keeperPct / PCT_DENOMINATOR;
        uint256 lootReward = amount - keeperReward;

        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount);
        (,,,,,uint16 customFailureThreshold,,,) = erc20FreePlay.getFreePlayPosition(1); // Alice Position ID is 1.
        assertEq(customFailureThreshold, 0, "customFailureThreshold for position should be 0");

        // All FP position's default to Tier.ONE which is 9500 failureThreshold (5% failure rate).
        vm.startPrank(Alice);
        erc20FreePlay.decreaseFailureThreshold(1, _customFailureThreshold); // new failure rate for position
        (,,,,,customFailureThreshold,,,) = erc20FreePlay.getFreePlayPosition(1);
        assertEq(customFailureThreshold, _customFailureThreshold, "customFailureThreshold for position should decrease");
        
        // Cannot decrease FP Position if claim is in progress
        vm.startPrank(Alice);
        erc20FreePlay.initiateClaim(1);
        vm.expectRevert();
        erc20FreePlay.decreaseFailureThreshold(1, 1337);

        // When setting customFailureThreshold, must always decrease, never stay the same or increase. 
        vm.expectRevert();
        erc20FreePlay.decreaseFailureThreshold(1, _customFailureThreshold);

        // Cannot make customFailureThreshold for a position 0, as this is the SPECIAL default value.
        vm.expectRevert();
        erc20FreePlay.decreaseFailureThreshold(1, 0);
        vm.stopPrank();

        // If owner doesn't match to position, cannot change it.
        vm.prank(Bob);
        vm.expectRevert();
        erc20FreePlay.decreaseFailureThreshold(1, 1337);

        // Claiming a position with custom failure rate changes the failure rate during claim.
        vm.prank(Bob);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Bob, amount);
        vm.startPrank(Bob);
        erc20FreePlay.decreaseFailureThreshold(2, 420); // 4.2% success rate, decreased to show it effects claims
        erc20FreePlay.initiateClaim(2); // Bob's Position ID is 2
        // 2nd rng is 922 in mocks, which is failure because our custom failure threshold is now 420 instead of 9500 default.
        // 922 > 420 = failure!
        (,uint256 requestId,,,,,,,) = erc20FreePlay.getFreePlayPosition(2); 
        coordinator.fulfillRandomWords(requestId, address(erc20FreePlay));
        // Should be failure, underlying tokens get sent to Loot.sol and keeper (Bob) instead of all to Bob.
        erc20FreePlay.finalizeClaim(2, false);  
        assertEq(erc20FreePlay.balanceOf(Bob), keeperReward, "Bob was the keeper here, got the 1% fee");
        assertEq(erc20FreePlay.balanceOf(address(loot)), lootReward, "Loot gets rest of position");
        vm.stopPrank();
    }

    function test_cleanUpExpiredPosition() public {
        uint256 amount = 200e18;
        uint64 expirationPeriod = 100 days;
        uint256 keeperReward = 100; // 1%

        // Prep user info for FP position
        vm.startPrank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.stopPrank();

        // Create FP Position
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount);
        (,,,,uint64 expiresAt,,,,) = erc20FreePlay.getFreePlayPosition(1); // First Position ID is 1.
        assertEq(expiresAt, block.timestamp + expirationPeriod, "Position expires at current time + expirationPeriod");

        // Cannot clean up non-expired position
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + expirationPeriod); // 1 second before expiration
        vm.expectRevert();
        erc20FreePlay.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        vm.warp(uint64(block.timestamp) - expirationPeriod); // Reset time
        vm.stopPrank();

        // Clean up expired position
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + expirationPeriod + 1);
        erc20FreePlay.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        
        assertEq(erc20FreePlay.balanceOf(Alice), amount * keeperReward / 10000, "should be right reward");
        assertEq(erc20FreePlay.balanceOf(address(loot)), amount - (amount * keeperReward / 10000), "should be right reward");
        (uint256 totalFreePlayCredits,,,,,) = erc20FreePlay.getUserInfo(Alice);
        assertEq(totalFreePlayCredits, 0, "All free play credits removed");

        // Position should no longer exist.
        (uint256 credits, 
        uint256 requestId, 
        address owner, 
        uint64 unlocksAt, 
        uint64 expiresAt1, 
        uint16 customFailureThreshold, 
        uint16 randomWord, 
        State claimStatus, 
        Tier claimTier) = erc20FreePlay.getFreePlayPosition(1); 

        assertEq(credits, 0, "Position should have no credits");
        assertEq(requestId, 0, "VRF request ID should not exist");
        assertEq(owner, address(0), "owner should be nobody");
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
        erc20FreePlay.toggleFreePlayStatus();
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.stopPrank();

        // Create FP Position
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount);
        (,,,,uint64 expiresAt,,,,) = erc20FreePlay.getFreePlayPosition(1); // First Position ID is 1.
        assertEq(expiresAt, block.timestamp + expirationPeriod, "Position expires at current time + expirationPeriod");

        // Initiate claim
        vm.startPrank(Alice);
        erc20FreePlay.initiateClaim(1);

        // Warp until it's expired
        vm.warp(block.timestamp + expirationPeriod + 69);
        vm.expectRevert();
        // Position is expired but cannot clean up because claim in progress.
        erc20FreePlay.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        vm.stopPrank();
    }

    function test_lootWithdrawals() public {
        uint256 amount = 200e18;
        uint64 expirationPeriod = 100 days;
        uint256 keeperReward = 100; // 1%

        // Prep and create FP Position
        vm.startPrank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount);

        // Expired position gets cleaned up
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + expirationPeriod + 1);
        erc20FreePlay.cleanUpExpiredPosition(1, false); // Alice's Position ID is 1.
        assertEq(erc20FreePlay.balanceOf(Alice), amount * keeperReward / 10000, "should be right reward");
        assertEq(erc20FreePlay.balanceOf(address(loot)), amount - (amount * keeperReward / 10000), "should be right reward");
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
        assertEq(erc20FreePlay.balanceOf(Bob), 69e18, "Bob should get the loot");
        loot.withdrawAll(Bob);
        assertEq(erc20FreePlay.balanceOf(Bob), amount - (amount * keeperReward / 10000), "Bob should get the rest");
        vm.stopPrank();
    }

    function test_initiateClaim_fulfillRandomWords() public {
        uint256 amount = 200e18;

        // Create FP position
        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // First FP Position ID is 1.
        (,uint256 requestId,,,,,uint16 randomWord, State claimStatus,) = erc20FreePlay.getFreePlayPosition(1); // First Position ID is 1.
        assertEq(requestId, 0, "VRF request ID should not exist yet");
        assertEq(randomWord, 0, "should have no random word yet");
        assertEq(uint(claimStatus), uint(State.UNINITIALIZED), "should be integer 0");

        // Initiate claim and fulfill the random word for this position.
        vm.startPrank(Alice);
        erc20FreePlay.initiateClaim(1); 
        (,uint256 requestIdForClaim,,,,,uint16 randomWordForClaim, State claimStatusForClaim,) = erc20FreePlay.getFreePlayPosition(1); 
        assertEq(requestIdForClaim, 1, "VRF request ID should now exist"); // Note: For non-mock VRF, requestID is a hash, NOT a counter!
        assertEq(randomWordForClaim, 0, "should still have no random word yet until fulfillRandomWords() is called");
        assertEq(uint(claimStatusForClaim), uint(State.CLAIM_IN_PROGRESS), "claim should now be in progress for position");
        
        // Mock the callback giving the position the random word back.
        coordinator.fulfillRandomWords(requestIdForClaim, address(erc20FreePlay)); 
        (,,,,,,uint16 randomWord1,,) = erc20FreePlay.getFreePlayPosition(1); 
        assertNotEq(randomWord1, randomWordForClaim, "random word now exists and will never be 0"); // [1, 10000] inclusive
        console.log("Random word generated for 1st position: ", randomWord1);
        vm.stopPrank(); 

        // Create another FP position and generate another random word (sanity check).
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount);
        vm.startPrank(Alice);
        erc20FreePlay.initiateClaim(2); // 2nd position for Alice
        (,uint256 requestId2,,,,,,,) = erc20FreePlay.getFreePlayPosition(2); 
        coordinator.fulfillRandomWords(requestId2, address(erc20FreePlay)); 
        (,,,,,,uint16 randomWord2,,) = erc20FreePlay.getFreePlayPosition(2); 
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
        erc20FreePlay.toggleFreePlayStatus();
        erc20FreePlay.setTimelock(timeLockPeriod);
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID is 1.

        // Position not matured
        vm.prank(Alice);
        vm.expectRevert(); 
        erc20FreePlay.initiateClaim(1); 

        // Position matured but Position.owner != msg.sender
        vm.warp(uint64(block.timestamp) + timeLockPeriod + 1);
        vm.prank(Bob);
        vm.expectRevert();
        erc20FreePlay.initiateClaim(1);

        // Position status cannot be CLAIM_IN_PROGRESS (multiple VRF requests successfully denied per position).
        vm.startPrank(Alice);
        erc20FreePlay.initiateClaim(1); // initiate claim goes through
        vm.expectRevert();
        erc20FreePlay.initiateClaim(1); // reverts

        // Position gets immediately cleaned up if it's expired and a claim is attempted
        vm.startPrank(Bob);
        erc20FreePlay.toggleFreePlayStatus();
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.prank(Owner);
        erc20FreePlay.transfer(Bob, amount); // Bob FP Position ID is 2.

        // Warp to expiration. Position automatically cleaned up
        vm.warp(block.timestamp + expirationPeriod + 1);
        vm.prank(Bob);
        erc20FreePlay.initiateClaim(2);
        assertEq(erc20FreePlay.balanceOf(Bob), keeperReward, "Bob gets keeper reward");
        assertEq(erc20FreePlay.balanceOf(address(loot)), lootReward, "Loot gets rest");
    }

    function test_finalizeClaim() public {
        uint256 amount = 200e18;
        uint256 keeperRewardPct = 100;
        uint256 PCT_DENOMINATOR = 10000;
        uint256 keeperReward = amount * keeperRewardPct / PCT_DENOMINATOR;
        uint256 lootReward = amount - keeperReward;
        // Create FP position
        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // First FP Position ID is 1.

        // Initiate claim, fulfillRandomWords, then finalize claim.
        // Should give Alice underlying tokens because RNG was success.
        vm.startPrank(Alice);
        erc20FreePlay.initiateClaim(1); 
        (,uint256 requestIdAlice,,,,,,,) = erc20FreePlay.getFreePlayPosition(1); 
        coordinator.fulfillRandomWords(requestIdAlice, address(erc20FreePlay)); 
        (,,,,,,uint16 randomWordAlice,,) = erc20FreePlay.getFreePlayPosition(1); 
        console.log("Random word generated for Alice's position: ", randomWordAlice);
        erc20FreePlay.finalizeClaim(1, false); // Keeper is Alice, it can also be anyone else.
        assertEq(erc20FreePlay.balanceOf(Alice), amount, "Alice should have received all underlying tokens");
        vm.stopPrank(); 

        // Failure claim result. `position.randomWord` must be > failureThreshold of tier.ONE of 9500 for example.
        vm.prank(Bob);
        erc20FreePlay.toggleFreePlayStatus();
        uint256 i = 2; // Starting position ID for Bob
        uint16 randomWordBob = 0;
        uint256 requestIdBob;

        while(true) {
            vm.prank(Owner);
            erc20FreePlay.transfer(Bob, amount); 
            vm.startPrank(Bob);
            erc20FreePlay.initiateClaim(i);
            vm.stopPrank();
            (,requestIdBob,,,,,,,) = erc20FreePlay.getFreePlayPosition(i); 
            coordinator.fulfillRandomWords(requestIdBob, address(erc20FreePlay)); 
            (,,,,,,randomWordBob,,) = erc20FreePlay.getFreePlayPosition(i); 
            console.log("Random word generated for Bob's position: ", randomWordBob);
            if (randomWordBob > 9500) break;
            i++; 
        }

        vm.prank(Charlie); // Keeper can be anyone, including Bob.
        erc20FreePlay.finalizeClaim(i, false); 
        assertEq(erc20FreePlay.balanceOf(Bob), 0, "Bob should receive nothing, claim failed");
        assertEq(erc20FreePlay.balanceOf(Charlie), keeperReward, "Charlie the keeper gets the fee");
        assertEq(erc20FreePlay.balanceOf(address(loot)), lootReward, "Loot gets the rest");
        vm.prank(Owner);
        loot.withdrawAll(Charlie); // Owner withdraws all to Charlie
        assertEq(erc20FreePlay.balanceOf(Charlie), keeperReward + lootReward, "Lucky Charlie");
    }

    function test_finalizeClaimReverts() public {
        // Should revert if random word is 0 or claim status is NOT claim in progress
        uint256 amount = 200e18;

        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount);

        vm.startPrank(Alice);
        vm.expectRevert();
        erc20FreePlay.finalizeClaim(1, false); // revert, not CLAIM_IN_PROGRESS
        erc20FreePlay.initiateClaim(1); // Initiate the claim, request RNG
        vm.expectRevert();
        erc20FreePlay.finalizeClaim(1, false); // CLAIM_IN_PROGRESS but no random word yet
    }

    function test_initiateMultipleClaims() public {
        uint256 amount = 200e18;

        // Create FP positions
        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.startPrank(Owner);
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 1
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 2
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 3
        vm.stopPrank();

        // Prep array of position IDs
        uint256[] memory positionIds = new uint256[](3);
        positionIds[0] = 1;
        positionIds[1] = 2;
        positionIds[2] = 3;

        // Initiate multiple claims
        vm.startPrank(Alice);
        erc20FreePlay.initiateMultipleClaims(positionIds); 
        vm.stopPrank();

        (,uint256 requestId1,,,,,,State claimStatus1,) = erc20FreePlay.getFreePlayPosition(1); 
        (,uint256 requestId2,,,,,,State claimStatus2,) = erc20FreePlay.getFreePlayPosition(2); 
        (,uint256 requestId3,,,,,,State claimStatus3,) = erc20FreePlay.getFreePlayPosition(3); 

        assertEq(requestId1, 1, "VRF request ID should now exist"); // Note: For non-mock VRF, requestID is a hash, NOT a counter!
        assertEq(requestId2, 2, "..."); 
        assertEq(requestId3, 3, "...");

        assertEq(uint(claimStatus1), uint(State.CLAIM_IN_PROGRESS), "claim should now be in progress for position");
        assertEq(uint(claimStatus2), uint(State.CLAIM_IN_PROGRESS), "...");
        assertEq(uint(claimStatus3), uint(State.CLAIM_IN_PROGRESS), "...");
    }

    function test_finalizeMultipleClaims() public {
        uint256 amount = 200e18;

        // Create FP positions
        vm.prank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        vm.startPrank(Owner);
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 1
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 2
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 3
        vm.stopPrank();

        // Prep array of position IDs
        uint256[] memory positionIds = new uint256[](3);
        positionIds[0] = 1;
        positionIds[1] = 2;
        positionIds[2] = 3;

        // Initiate multiple claims
        vm.prank(Alice);
        erc20FreePlay.initiateMultipleClaims(positionIds); 

        // requestId's are just 1, 2, 3. Coincidence that they correspond to position IDs.
        // Note: For non-mock VRF, requestID is a hash, NOT a counter!
        coordinator.fulfillRandomWords(1, address(erc20FreePlay)); // randomWord = 6462, result = success
        coordinator.fulfillRandomWords(2, address(erc20FreePlay)); // randomWord = 922, result = success
        coordinator.fulfillRandomWords(3, address(erc20FreePlay)); // randomWord = 5940, result = success

        vm.prank(Alice);
        erc20FreePlay.finalizeMultipleClaims(positionIds);
        assertEq(erc20FreePlay.balanceOf(Alice), amount*3, "winner winner winner chicken dinner");
    }

    function test_cleanUpMultipleExpiredPositions() public {
        uint256 amount = 200e18;
        uint64 expirationPeriod = 69 days;

        // Create FP positions
        vm.startPrank(Alice);
        erc20FreePlay.toggleFreePlayStatus();
        erc20FreePlay.setExpiration(expirationPeriod);
        vm.stopPrank();
        vm.startPrank(Owner);
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 1
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 2
        erc20FreePlay.transfer(Alice, amount); // Alice FP Position ID 3
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
        erc20FreePlay.cleanUpMultipleExpiredPositions(positionIds); 
        assertEq(erc20FreePlay.balanceOf(Alice), 6e18, "gets keeper rewards"); // 1% * 600 = 6
        assertEq(erc20FreePlay.balanceOf(address(loot)), 594e18, "gets the rest");
    }
}