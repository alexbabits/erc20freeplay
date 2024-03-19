// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20FreePlay, ERC20} from "./ERC20FreePlay.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @dev This example FP Token contract is complicated and must be handled carefully, so let me explain...
 *
 * There are two "types" of FP tokens that you can deploy: "Standalone" and "Wrapper".
 * "Standalone" = The FP token is created with the intent to NOT be associated with any currently existing token. (fpYOUR_NOVEL_TOKEN)
 * "Wrapper" = The FP token is created with the intent to be SOLELY associated with a currently existing token. (fpLINK for LINK)
 *  
 * Instead of making a FP Token for each type, both functionalities are merged into this example.
 * The test suite uses this FPToken contract to test both kinds of FP Token types and their functionality.
 *
 * * * * * * * * * * * * * * * DEPLOYMENT WARNINGS BELOW  * * * * * * * * * * * * * * * * * 
 *
 * Note: "Standalone" FP Token = DO NOT deploy or set a transmuter, and DO NOT deploy with a `transmuterMint()` function.
 * Note: "Wrapper" FP Token = DO NOT mint any FP tokens upon deployment with `_mint()`, and DO NOT deploy with `typicalMint()` function.
 * 
 * TODO: Ideally, separate FP Token contract for each type and modify deployments and testing suite appropriately.
 */
contract FPToken is ERC20FreePlay {

    constructor(
        address owner, 
        uint256 initialSupply,
        uint64 _subscriptionId, 
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        address _vrfCoordinator, 
        address _escrow, 
        address _loot
    ) 
        ERC20("Free Play Example", "fpEXAMPLE")
        VRFConsumerBaseV2(_vrfCoordinator)
        Ownable(owner)
    {
        setSubscriptionId(_subscriptionId);
        setKeyHash(_keyHash);
        setCallbackGasLimit(_callbackGasLimit);
        setRequestConfirmations(_requestConfirmations);
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        _setEscrow(_escrow);
        _setLoot(_loot);
        _mint(owner, initialSupply); // Note: DO NOT mint any tokens upon deployment if making a Wrapper FP token. 
    }

    // Note: This function should ONLY be implemented for type "Standalone" FP Tokens. (If you want minting functionality).
    // Note: On Mainnet, add whatever access restrictions you need to control the actor(s) that can mint more FP Tokens.
    function typicalMint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Note: This function is required for type "Wrapper" FP Tokens, and should ONLY be implemented for this type.
    function transmuterMint(address to, uint256 amount) external {
        if (msg.sender != transmuter) revert NotWhitelistedCaller(msg.sender);
        _mint(to, amount);
    }
}