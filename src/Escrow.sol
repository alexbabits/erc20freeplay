// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {ErrorsEventsEnum} from "./ErrorsEventsEnum.sol";
/**
 * @dev Base template contract that holds all underlying tokens for free play credits. Completely immutable and unchangable after deployment. 
 */
abstract contract Escrow is ErrorsEventsEnum {
    using SafeERC20 for IERC20;
    address private _freePlayToken;
    address private _loot;
    uint8 private immutable SUCCESS = 3;

    function transferUnderlyingTokensBasedOnResult(address user, uint256 value, uint8 result) external {
        if (msg.sender != _freePlayToken) revert NotFreePlayToken();
        result == SUCCESS ? IERC20(_freePlayToken).safeTransfer(user, value) : IERC20(_freePlayToken).safeTransfer(_loot, value);
    }

    function transferUnderlyingTokens(address to, uint256 value) external {
        if (msg.sender != _freePlayToken) revert NotFreePlayToken();
        IERC20(_freePlayToken).safeTransfer(to, value);
    }
    
    function _setFreePlayTokenAddress(address freePlayToken) internal {
        if (_freePlayToken != address(0)) revert AddressAlreadySet();
        if (freePlayToken == address(0)) revert ZeroAddress();
        _freePlayToken = freePlayToken;
    }

    function _setLootAddress(address loot) internal {
        if (_loot != address(0)) revert AddressAlreadySet();
        if (loot == address(0)) revert ZeroAddress();
        _loot = loot;
    }
}