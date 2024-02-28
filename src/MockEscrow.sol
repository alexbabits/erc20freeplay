// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Escrow} from "./Escrow.sol";

contract MockEscrow is Escrow, Ownable2Step {

    constructor (address owner) Ownable(owner) {   
    }

    /**
     * @dev Set Free Play Token address after deployment. Can only be set once.
     */ 
    function setFreePlayTokenAddress(address _freePlayToken) external onlyOwner {
        _setFreePlayTokenAddress(_freePlayToken);
    }

    /**
     * @dev Set Loot address after deployment. Can only be set once.
     */ 
    function setLootAddress(address _loot) external onlyOwner {
        _setLootAddress(_loot);
    }
}

// Override functions to include custom logic where needed.
// Make sure to include the authorization check (onlyOwner) or (require msg.sender is _freePlayToken).