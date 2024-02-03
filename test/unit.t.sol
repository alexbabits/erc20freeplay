// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {MockDeferredToken} from "../src/MockDeferredToken.sol";

contract DeferredTokenTest is Test {
    MockDeferredToken mockDeferredToken;

    address owner;
    address accountTwo = address(2);
    address accountThree = address(3);

    uint256 initialSupply = 1e27; // 1 billion initial supply, 1e18 * 1e9.

    uint8 private immutable UNINITIALIZED = 0;
    uint8 private immutable OFF = 1;
    uint8 private immutable ON = 2;

    function setUp() public {
        owner = address(this);
        mockDeferredToken = new MockDeferredToken(initialSupply);
    }

    function test_deployment() public {
        assertEq(mockDeferredToken.totalSupply(), initialSupply, "Incorrect total supply");
        assertEq(mockDeferredToken.balanceOf(owner), initialSupply, "Owner should have all tokens initially");
    }

    function test_transfer_withoutManualClaim() public {
        uint256 amountOne = 500 ether; // Equivalent to 500 tokens
        uint256 amountTwo = 200 ether; // Equivalent to 200 tokens

        mockDeferredToken.transfer(accountTwo, amountOne); // Using ERC20 `transfer()`.
        assertEq(mockDeferredToken.balanceOf(accountTwo), amountOne, "accountTwo should have 500 tokens");

        vm.prank(accountTwo);
        mockDeferredToken.transfer(accountThree, amountTwo);
        assertEq(mockDeferredToken.balanceOf(owner), initialSupply - amountOne, "Owner should have remaining tokens");
        assertEq(mockDeferredToken.balanceOf(accountThree), amountTwo, "accountThree should have 200 tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountThree), 0, "accountThree should have no pending tokens");
        assertEq(mockDeferredToken.balanceOf(accountTwo), amountOne - amountTwo, "accountTwo should have 300 tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), 0, "accountTwo should have no pending tokens");
    }

    function test_transferFrom_withoutManualClaim() public {
        uint256 amount = 500 ether;
        mockDeferredToken.approve(accountTwo, amount);
        vm.prank(accountTwo);
        mockDeferredToken.transferFrom(owner, accountThree, amount);
        assertEq(mockDeferredToken.balanceOf(owner), initialSupply - amount, "Owner should have remaining tokens");
        assertEq(mockDeferredToken.balanceOf(accountThree), amount, "accountThree should have 500 tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountThree), 0, "accountThree should have no pending tokens");
    }

    function test_toggleClaimStatus() public {
        vm.startPrank(accountTwo);
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), UNINITIALIZED, "doesnt match");
        mockDeferredToken.toggleClaimStatus();
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), ON, "doesnt match");
        mockDeferredToken.toggleClaimStatus();
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), OFF, "doesnt match");
        mockDeferredToken.toggleClaimStatus();
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), ON, "doesnt match");
        vm.stopPrank();
    }

    function test_transfer_withManualClaim_claimSpecificAmount_claimAll() public {
        uint256 amountOne = 500 ether; 
        uint256 amountTwo = 123 ether;

        vm.startPrank(accountTwo);
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), UNINITIALIZED, "doesnt match");
        mockDeferredToken.toggleClaimStatus();
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), ON, "doesnt match");
        vm.stopPrank();

        vm.prank(owner);
        mockDeferredToken.transfer(accountTwo, amountOne); 
        assertEq(mockDeferredToken.balanceOf(accountTwo), 0, "accountTwo should have 0 tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), amountOne, "accountTwo should have 500 pending tokens");

        vm.startPrank(accountTwo);
        mockDeferredToken.claimSpecificAmount(amountTwo);
        assertEq(mockDeferredToken.balanceOf(accountTwo), amountTwo, "accountTwo should have some tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), amountOne - amountTwo, "accountTwo should have some pending tokens");

        mockDeferredToken.claimAll();
        assertEq(mockDeferredToken.balanceOf(accountTwo), amountOne, "accountTwo should have some tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), 0, "accountTwo should have some pending tokens");
    }

    function test_transferFrom_withManualClaim_claimSpecificAmount_claimAll() public {
        uint256 amountOne = 500 ether; 
        uint256 amountTwo = 123 ether;

        vm.prank(accountThree);
        mockDeferredToken.toggleClaimStatus();
        vm.stopPrank();

        mockDeferredToken.approve(accountTwo, amountOne);

        vm.prank(accountTwo);
        mockDeferredToken.transferFrom(owner, accountThree, amountOne);
        assertEq(mockDeferredToken.balanceOf(owner), initialSupply - amountOne, "owner should have remaining tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountThree), amountOne, "should have 500 pending tokens");

        vm.startPrank(accountThree);
        mockDeferredToken.claimSpecificAmount(amountTwo);
        assertEq(mockDeferredToken.balanceOf(accountThree), amountTwo, "should have claimed some tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountThree), amountOne - amountTwo, "should still have some pending tokens");

        mockDeferredToken.claimAll();
        assertEq(mockDeferredToken.balanceOf(accountThree), amountOne, "should have all tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountThree), 0, "should have no pending tokens");
    }

    function test_claimAllFailures() public {   
        uint256 amount = 500 ether;

        // Can't claim if no pending balance
        vm.startPrank(accountTwo);
        mockDeferredToken.toggleClaimStatus();
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), ON, "doesnt match");
        vm.expectRevert();
        mockDeferredToken.claimAll();
        vm.stopPrank();

        // Can't claim if not ON
        vm.startPrank(owner);
        mockDeferredToken.transfer(accountTwo, amount); // Transfers while status is still ON for recipient
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), amount, "should have pending tokens");
        vm.stopPrank();

        vm.startPrank(accountTwo);
        mockDeferredToken.toggleClaimStatus(); // toggles OFF
        vm.expectRevert();
        mockDeferredToken.claimAll();

        // Double check we can toggle again and claim
        mockDeferredToken.toggleClaimStatus();
        mockDeferredToken.claimAll();
        assertEq(mockDeferredToken.balanceOf(accountTwo), amount, "should have all tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), 0, "should have no pending tokens"); 
    }

    function test_claimSpecificAmountFailures() public {
        uint256 amount = 500 ether;

        // Can't claim 0 amount
        vm.startPrank(accountTwo);
        mockDeferredToken.toggleClaimStatus();
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), ON, "doesnt match");
        vm.expectRevert();
        mockDeferredToken.claimSpecificAmount(0);

        // Can't claim more pending tokens than the mapping shows
        vm.expectRevert();
        mockDeferredToken.claimSpecificAmount(1);
        vm.stopPrank();
        
        // Double check with non-zero amount too. First need to send tokens.
        vm.startPrank(owner);
        mockDeferredToken.transfer(accountTwo, amount); // Transfers while status is ON for recipient
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), amount, "should have pending tokens");
        vm.stopPrank();
        
        vm.startPrank(accountTwo);
        vm.expectRevert();
        mockDeferredToken.claimSpecificAmount(amount + 1);
        mockDeferredToken.claimSpecificAmount(amount);
        assertEq(mockDeferredToken.balanceOf(accountTwo), amount, "should have all tokens");
    }

    function test_mint_withoutManualClaim() public {
        uint256 amount = 500 ether;
        vm.startPrank(accountTwo);

        uint256 totalSupplyBefore = mockDeferredToken.totalSupply();
        mockDeferredToken.mint(accountTwo, amount);
        uint256 totalSupplyAfter = mockDeferredToken.totalSupply();

        assertEq(mockDeferredToken.balanceOf(accountTwo), amount, "should have 500 tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), 0, "should have no pending tokens");
        assertEq(totalSupplyAfter, totalSupplyBefore + amount, "supply should have increased");
    }

    // Mints should credit users pending balance if their manual claim is enabled,
    // UNLESS user is calling `claimAll()` or `claimSpecificAmount()`, in which case this is a real mint
    // And should credit the user's real balance and increase the total supply.
    function test_mint_withManualClaim() public {
        uint256 amount = 500 ether;
        
        vm.startPrank(accountTwo);
        mockDeferredToken.toggleClaimStatus();
        assertEq(mockDeferredToken.manualClaimStatus(accountTwo), ON, "doesnt match");

        uint256 totalSupplyBefore = mockDeferredToken.totalSupply();
        mockDeferredToken.mint(accountTwo, amount);
        uint256 totalSupplyAfter = mockDeferredToken.totalSupply();

        // Total supply doesn't change when mint is credit to user with manual claim status enabled.
        assertEq(mockDeferredToken.balanceOf(accountTwo), 0, "accountTwo should have 500 tokens");
        assertEq(mockDeferredToken.pendingBalanceOf(accountTwo), amount, "should have no pending tokens");
        assertEq(totalSupplyBefore, totalSupplyAfter, "supply doesnt increase");
    }
}