// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {ERC20FreePlay} from "../src/ERC20FreePlay.sol";
import {Escrow} from "../src/Escrow.sol";
import {Loot} from "../src/Loot.sol";
/*
contract FreePlayTokenTest is Test {
    MockFreePlayToken mockFreePlayToken;
    MockEscrow mockEscrow;
    Loot loot;

    address Owner;
    address Alice = address(2);
    address Bob = address(3);

    uint256 initialSupply = 1e27; // 1 billion initial supply, 1e18 * 1e9.

    uint8 private immutable UNINITIALIZED = 0;
    uint8 private immutable OFF = 1;
    uint8 private immutable ON = 2;

    uint8 private immutable FAILURE = 0;
    uint8 private immutable SUCCESS = 1;

    function setUp() public {
        Owner = address(this);
        mockEscrow = new MockEscrow(Owner);
        loot = new Loot(Owner);
        mockFreePlayToken = new MockFreePlayToken(initialSupply, address(mockEscrow), address(loot));
        mockEscrow.setFreePlayTokenAddress(address(mockFreePlayToken));
        mockEscrow.setLootAddress(address(loot));
        loot.setFreePlayTokenAddress(address(mockFreePlayToken));
    }

    function test_deployment() public {
        // Maybe add more relevant things here now that it's expanding.
        assertEq(mockFreePlayToken.totalSupply(), initialSupply, "Incorrect total supply");
        assertEq(mockFreePlayToken.balanceOf(Owner), initialSupply, "Owner should have all tokens initially");
    }

    // When RNG is past threshold, this properly send funds to Loot instead of Alice. (RNG > 98 this test passes properly)
    function test_claim_rng_failures() public {
        uint256 amountOne = 500 ether; 
        uint256 amountTwo = 123 ether;

        // alice turns on free play status, so all received tokens are re-directed to Escrow contract.
        vm.startPrank(Alice);
        assertEq(mockFreePlayToken.freePlayStatus(Alice), UNINITIALIZED, "doesnt match");
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), ON, "doesnt match");
        vm.stopPrank();

        // successfully gives Escrow the 500 tokens, and updates Alice's free play credits.
        vm.prank(Owner);
        mockFreePlayToken.transfer(Alice, amountOne); 
        assertEq(mockFreePlayToken.balanceOf(Alice), 0, "Alice should have 0 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), amountOne, "Alice should have 500 free play credits");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amountOne, "Escrow should have the 500 tokens");

        // specific amount of claimed funds go to Loot because it fails (RNG too high).
        vm.startPrank(Alice);
        mockFreePlayToken.claimSpecificAmount(amountTwo); // THIS WILL FAIL WHEN RNG IS TOO HIGH.
        assertEq(mockFreePlayToken.balanceOf(address(loot)), amountTwo, "Loot should have some tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), amountOne - amountTwo, "Alice should have some free play credits still");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amountOne - amountTwo, "Escrow should have some tokens still");

        // remaining amount of claimed funds go to Loot because it fails (RNG too high).
        mockFreePlayToken.claimAll(); // THIS WILL FAIL WHEN RNG IS TOO HIGH.
        assertEq(mockFreePlayToken.balanceOf(address(loot)), amountOne, "Loot should have all 500 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), 0, "Alice should have no tokens");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), 0, "Escrow should have no tokens");
    }

    function test_transfer_free_play_off() public {
        uint256 amountOne = 500 ether; // Equivalent to 500 tokens
        uint256 amountTwo = 200 ether; // Equivalent to 200 tokens

        mockFreePlayToken.transfer(Alice, amountOne); // Using ERC20 `transfer()`.
        assertEq(mockFreePlayToken.balanceOf(Alice), amountOne, "Alice should have 500 tokens");

        vm.prank(Alice);
        mockFreePlayToken.transfer(Bob, amountTwo);
        assertEq(mockFreePlayToken.balanceOf(Owner), initialSupply - amountOne, "Owner should have remaining tokens");
        assertEq(mockFreePlayToken.balanceOf(Bob), amountTwo, "Bob should have 200 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Bob), 0, "Bob should have no free play credits");
        assertEq(mockFreePlayToken.balanceOf(Alice), amountOne - amountTwo, "Alice should have 300 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), 0, "Alice should have no free play credits");
    }

    function test_transferFrom_free_play_off() public {
        uint256 amount = 500 ether;
        mockFreePlayToken.approve(Alice, amount);
        vm.prank(Alice);
        mockFreePlayToken.transferFrom(Owner, Bob, amount);
        assertEq(mockFreePlayToken.balanceOf(Owner), initialSupply - amount, "Owner should have remaining tokens");
        assertEq(mockFreePlayToken.balanceOf(Bob), amount, "Bob should have 500 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Bob), 0, "Bob should have no free play credits");
    }

    function test_toggleFreePlayStatus() public {
        vm.startPrank(Alice);
        assertEq(mockFreePlayToken.freePlayStatus(Alice), UNINITIALIZED, "doesnt match");
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), ON, "doesnt match");
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), OFF, "doesnt match");
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), ON, "doesnt match");
        vm.stopPrank();
    }

    function test_transfer_and_claims_free_play_on() public {
        uint256 amountOne = 500 ether; 
        uint256 amountTwo = 123 ether;

        // alice turns on free play status, so all received tokens are re-directed to Escrow contract.
        vm.startPrank(Alice);
        assertEq(mockFreePlayToken.freePlayStatus(Alice), UNINITIALIZED, "doesnt match");
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), ON, "doesnt match");
        vm.stopPrank();

        // successfully gives Escrow the 500 tokens, and updates Alice's free play credits.
        vm.prank(Owner);
        mockFreePlayToken.transfer(Alice, amountOne); 
        assertEq(mockFreePlayToken.balanceOf(Alice), 0, "Alice should have 0 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), amountOne, "Alice should have 500 free play credits");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amountOne, "Escrow should have the 500 tokens");

        // specific amount of claimed funds go to Alice
        vm.startPrank(Alice);
        mockFreePlayToken.claimSpecificAmount(amountTwo);
        assertEq(mockFreePlayToken.balanceOf(Alice), amountTwo, "Alice should have some tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), amountOne - amountTwo, "Alice should have some free play credits still");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amountOne - amountTwo, "Escrow should have some tokens still");

        // remaining amount of claimed funds go to Alice
        mockFreePlayToken.claimAll();
        assertEq(mockFreePlayToken.balanceOf(Alice), amountOne, "Alice should have all 500 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), 0, "Alice should have no tokens");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), 0, "Escrow should have no tokens");
    }

    function test_transferFrom_and_claims_free_play_on() public {
        uint256 amountOne = 500 ether; 
        uint256 amountTwo = 123 ether;

        vm.prank(Bob);
        mockFreePlayToken.toggleFreePlayStatus();
        vm.stopPrank();

        mockFreePlayToken.approve(Alice, amountOne);

        vm.prank(Alice);
        mockFreePlayToken.transferFrom(Owner, Bob, amountOne);
        assertEq(mockFreePlayToken.balanceOf(Owner), initialSupply - amountOne, "Owner should have remaining tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Bob), amountOne, "should have 500 free play credits");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amountOne, "Escrow should have the 500 tokens");

        vm.startPrank(Bob);
        mockFreePlayToken.claimSpecificAmount(amountTwo);
        assertEq(mockFreePlayToken.balanceOf(Bob), amountTwo, "should have claimed some tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Bob), amountOne - amountTwo, "should still have some free play credits");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amountOne - amountTwo, "Escrow should have some tokens still");

        mockFreePlayToken.claimAll();
        assertEq(mockFreePlayToken.balanceOf(Bob), amountOne, "should have all tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Bob), 0, "should have no free play credits");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), 0, "Escrow should have no tokens");
    }

    function test_claimAll_Reverts() public {   
        uint256 amount = 500 ether;

        // Can't claim if no free play credits.
        vm.startPrank(Alice);
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), ON, "doesnt match");
        vm.expectRevert();
        mockFreePlayToken.claimAll();
        vm.stopPrank();

        // Can't claim if not ON
        vm.startPrank(Owner);
        mockFreePlayToken.transfer(Alice, amount); // Transfers while status is still ON for recipient
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), amount, "should have free play credits");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amount, "Escrow should have the tokens");
        vm.stopPrank();

        vm.startPrank(Alice);
        mockFreePlayToken.toggleFreePlayStatus(); // toggles OFF
        vm.expectRevert();
        mockFreePlayToken.claimAll();

        // Double check we can toggle again and claim
        mockFreePlayToken.toggleFreePlayStatus();
        mockFreePlayToken.claimAll();
        assertEq(mockFreePlayToken.balanceOf(Alice), amount, "should have all tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), 0, "should have no free play credits"); 
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), 0, "Escrow should have no tokens");
    }


    function test_claimSpecificAmount_Reverts() public {
        uint256 amount = 500 ether;

        // Can't claim 0 amount
        vm.startPrank(Alice);
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), ON, "doesnt match");
        vm.expectRevert();
        mockFreePlayToken.claimSpecificAmount(0);

        // Can't claim more free play credits than the mapping shows
        vm.expectRevert();
        mockFreePlayToken.claimSpecificAmount(1);
        vm.stopPrank();
        
        // Double check with non-zero amount too. First need to send tokens.
        vm.startPrank(Owner);
        mockFreePlayToken.transfer(Alice, amount); // Transfers while status is ON for recipient
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), amount, "should have free play credits");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amount, "Escrow should have the tokens");
        vm.stopPrank();
        
        vm.startPrank(Alice);
        vm.expectRevert();
        mockFreePlayToken.claimSpecificAmount(amount + 1); // reverts
        mockFreePlayToken.claimSpecificAmount(amount); // doesn't revert
        assertEq(mockFreePlayToken.balanceOf(Alice), amount, "should have all tokens");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), 0, "Escrow should have no tokens");
    }

    function test_mint_free_play_off() public {
        uint256 amount = 500 ether;
        vm.startPrank(Alice);

        uint256 totalSupplyBefore = mockFreePlayToken.totalSupply();
        mockFreePlayToken.mint(Alice, amount);
        uint256 totalSupplyAfter = mockFreePlayToken.totalSupply();

        assertEq(mockFreePlayToken.balanceOf(Alice), amount, "should have 500 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), 0, "should have no free play credits");
        assertEq(totalSupplyAfter, totalSupplyBefore + amount, "supply should have increased");
    }

    function test_mint_free_play_on() public {
        uint256 amount = 500 ether;
        
        vm.startPrank(Alice);
        mockFreePlayToken.toggleFreePlayStatus();
        assertEq(mockFreePlayToken.freePlayStatus(Alice), ON, "doesnt match");

        uint256 totalSupplyBefore = mockFreePlayToken.totalSupply();
        mockFreePlayToken.mint(Alice, amount);
        uint256 totalSupplyAfter = mockFreePlayToken.totalSupply();

        // Total supply doesn't change when mint is credit to user with free play status enabled.
        assertEq(mockFreePlayToken.balanceOf(Alice), 0, "Alice should have 0 tokens");
        assertEq(mockFreePlayToken.freePlayCreditsOf(Alice), amount, "should have 500 free play credits");
        assertLt(totalSupplyBefore, totalSupplyAfter, "supply increases, mints goes to Escrow");
        assertEq(mockFreePlayToken.balanceOf(address(mockEscrow)), amount, "shit should be this");
    }
}
*/