// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ErrorsEventsEnums} from "./ErrorsEventsEnums.sol";

contract Escrow is Ownable2Step, ErrorsEventsEnums {
    using SafeERC20 for IERC20;
    address private freePlayToken;
    address private loot;

    constructor (address owner) Ownable(owner) {}

    function transferUnderlyingTokens(address to, uint256 value) external {
        if (msg.sender != freePlayToken) revert NotFreePlayToken();
        IERC20(freePlayToken).safeTransfer(to, value);
    }

    function setFreePlayTokenAddress(address _freePlayToken) external onlyOwner {
        if (freePlayToken != address(0)) revert AddressAlreadySet();
        if (_freePlayToken == address(0)) revert ZeroAddress();
        freePlayToken = _freePlayToken;
    }

    function setLootAddress(address _loot) external onlyOwner {
        if (loot != address(0)) revert AddressAlreadySet();
        if (_loot == address(0)) revert ZeroAddress();
        loot = _loot;
    }
}