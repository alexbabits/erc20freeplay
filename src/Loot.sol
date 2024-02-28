/*
Tokens end up in this contract from:
    1. Failure of redemption via unlucky RNG during a claim
    2. Donations made to this contract to boost their win chance

Whoever owns `Loot.sol` contract can withdraw the funds to any address they want.
When this contract is deployed, it needs a reference to the `_freePlayToken`.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {ErrorsEventsEnum} from "./ErrorsEventsEnum.sol";

contract Loot is Ownable2Step, ErrorsEventsEnum {

    using SafeERC20 for IERC20;
    address private _freePlayToken;

    constructor (address owner) Ownable(owner) {
    }

    function setFreePlayTokenAddress(address freePlayToken) external onlyOwner {
        if (_freePlayToken != address(0)) revert AddressAlreadySet();
        if (freePlayToken == address(0)) revert ZeroAddress();
        _freePlayToken = freePlayToken;
    }

    function withdrawSpecificAmount(uint256 amount, address to) external onlyOwner {
        IERC20(_freePlayToken).safeTransfer(to, amount);
    }

    function withdrawAll(address to) external onlyOwner {
        uint256 entireBalance = IERC20(_freePlayToken).balanceOf(address(this));
        IERC20(_freePlayToken).safeTransfer(to, entireBalance);
    }
}