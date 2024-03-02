// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {ERC20FreePlay, EnumsEventsErrors} from "../src/ERC20FreePlay.sol";
import {Escrow} from "../src/Escrow.sol";
import {Loot} from "../src/Loot.sol";

// 1. @audit TODO: With reverts, plug in the custom errors, make sure they match
// 2. @audit TODO: With events, make sure all events are emitted correctly
// 3. @audit TODO: Should probably test front-end getters return the right amounts for tier/next tier too

contract FreePlayTokenTest is Test, EnumsEventsErrors {
    ERC20FreePlay erc20FreePlay;
    Escrow escrow;
    Loot loot;

    address Owner;
    address Alice = address(2);
    address Bob = address(3);

    uint256 initialSupply = 1e27; // 1 billion initial supply, 1e18 * 1e9.
    uint64 subscriptionId = 9745; // VRF subscription ID

    function setUp() public {
        Owner = address(this);
        escrow = new Escrow(Owner);
        loot = new Loot(Owner);
        erc20FreePlay = new ERC20FreePlay(Owner, subscriptionId, initialSupply, address(escrow), address(loot));
        escrow.setFreePlayTokenAddress(address(erc20FreePlay));
        escrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(erc20FreePlay));
    }

    function test_deployment() public {
        //@audit add more things here.
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
        vm.startPrank(Alice);

        uint256 totalSupplyBefore = erc20FreePlay.totalSupply();
        erc20FreePlay.mint(Alice, amount);
        uint256 totalSupplyAfter = erc20FreePlay.totalSupply();

        assertEq(erc20FreePlay.balanceOf(Alice), amount, "should have 500 tokens");
        assertEq(totalSupplyAfter, totalSupplyBefore + amount, "supply should have increased");
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
        //@audit include revert conditions with asserts to verify
        erc20FreePlay.setKeeperReward(420);
        erc20FreePlay.setPenaltyFee(6969);
        erc20FreePlay.setCallbackGasLimit(420000);
        erc20FreePlay.setRequestConfirmations(69);
        erc20FreePlay.setSubscriptionId(9696);
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
        
        vm.startPrank(Alice);
        erc20FreePlay.toggleFreePlayStatus();

        uint256 totalSupplyBefore = erc20FreePlay.totalSupply();
        erc20FreePlay.mint(Alice, amount);
        uint256 totalSupplyAfter = erc20FreePlay.totalSupply();

        assertEq(erc20FreePlay.balanceOf(Alice), 0, "Alice should have 0 tokens");
        (uint256 credits,,,,,,,,) = erc20FreePlay.getFreePlayPosition(1); // Alice's position ID is 1.
        assertEq(credits, 500e18, "Alice should be credited 100 free play");
        assertLt(totalSupplyBefore, totalSupplyAfter, "supply should increase, mints goes to Escrow");
        assertEq(erc20FreePlay.balanceOf(address(escrow)), amount, "Escrow should have gotten the tokens");
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

        // @audit Test that you can't donate during a claim.
        // @audit Consider fuzzing this function for different donation amounts to match the threshold
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

        // emergency unlock the position.
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + (timeLockPeriod / 2)); // Not yet unlocked
        erc20FreePlay.emergencyUnlock(1); // Alice's Posiiton ID is 1.
        (uint256 credits,,,uint64 unlocksAt,uint64 expiresAt,,,,) = erc20FreePlay.getFreePlayPosition(1);
        assertEq(credits, amount / 2, "FP credits should be slashed by the penalty fee of 50%");
        assertEq(unlocksAt, block.timestamp, "Position should now be immediately unlocked");
        assertEq(expiresAt, type(uint64).max, "For simplicity, emergency unlocked positions will not expire");
        assertEq(erc20FreePlay.balanceOf(address(loot)), amount / 2, "Loot immediately receives penalty amount underlying tokens");
        (uint256 totalFreePlayCredits,,,,,) = erc20FreePlay.getUserInfo(Alice);
        assertEq(totalFreePlayCredits, amount / 2, "Alice total tracked FP credits must also go down");
        // @audit in future, test the initiateClaim() here to verify you can claim it right after an unlock.
        // @audit If position has a claim in progress, cannot emergency unlock

        // Cannot emergency unlock FP position that has already been emergency unlocked.
        vm.expectRevert();
        erc20FreePlay.emergencyUnlock(1);
        vm.stopPrank();

        // Cannot emergency unlock FP position that is already matured past its timelock.
        vm.prank(Owner);
        erc20FreePlay.transfer(Alice, amount); // 2nd FP Position
        vm.startPrank(Alice);
        vm.warp(uint64(block.timestamp) + timeLockPeriod); // Position matured.
        vm.expectRevert();
        erc20FreePlay.emergencyUnlock(2); // Alice's Position ID is 2.
        vm.stopPrank();

        // If owner doesn't match, cannot unlock
        vm.prank(Bob);
        vm.expectRevert();
        erc20FreePlay.emergencyUnlock(1);
    }   

    function test_decreaseFailureThreshold() public {
        // Can only go down from your current position Tier.
        /*
        function decreaseFailureThreshold(uint256 _positionId, uint16 newFailureThreshold) external {
            FreePlayPosition storage position = freePlayPosition[_positionId];
            if (position.owner != msg.sender) revert NotOwnerOfPosition(msg.sender, position.owner);
            if (position.claimStatus == State.CLAIM_IN_PROGRESS) revert ClaimInProgress();
            Tier userTier = position.claimTier;
            uint16 oldFailureThreshold = position.customFailureThreshold == 0 
                ? globalTierInfo[userTier].failureThreshold 
                : position.customFailureThreshold;
            if (newFailureThreshold == 0 || newFailureThreshold >= oldFailureThreshold) revert InvalidCustomFailureThreshold();
            position.customFailureThreshold = newFailureThreshold;
            emit CustomFailureThresholdChanged(position.owner, _positionId, newFailureThreshold, oldFailureThreshold);
        }
    */
    }

    function test_cleanUpExpiredPosition() public {
        // 1. Create Expired position
        // 2. Clean it up
    }

    function test_cleanUpMultipleExpiredPositions() public {

    }

    function test_initiateClaim() public {
        // 1. Claim in progress reverts
        // Test all reverts
    }

    function test_initiateMultipleClaims() public {

    }

    function test_finalizeClaims() public {
        // 1. Initiate Claim
        // 2. Mock for VRF response (Requires a lot of work here).
        // 3. Finalize Claim
    }

    function test_finalizeMultipleClaims() public {
        // 1. Initiate Claim
        // 2. Mock for VRF response (Requires a lot of work here).
        // 3. Finalize Claim
    }

    function test_lootWithdrawals() public {
        // 1. Loot withdraw specific amount (must have loot in the contract from an expired or failed claim pos)
        // 2. Loot withdrawal all (must have loot in the contract from an expired or failed claim pos)
    }
}