// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EnumsEventsErrors} from "./EnumsEventsErrors.sol";

contract Loot is Ownable2Step, EnumsEventsErrors {
    using SafeERC20 for IERC20;
    address private freePlayToken;

    constructor (address owner) Ownable(owner) {}

    function setFreePlayTokenAddress(address _freePlayToken) external onlyOwner {
        if (freePlayToken != address(0)) revert AddressAlreadySet(freePlayToken);
        if (_freePlayToken == address(0)) revert ZeroAddress();
        freePlayToken = _freePlayToken;
        emit AddressSet(_freePlayToken);
    }

    function withdrawSpecificAmount(uint256 amount, address to) external onlyOwner {
        IERC20(freePlayToken).safeTransfer(to, amount);
        emit LootWithdrawal(amount, to);
    }

    function withdrawAll(address to) external onlyOwner {
        uint256 entireBalance = IERC20(freePlayToken).balanceOf(address(this));
        IERC20(freePlayToken).safeTransfer(to, entireBalance);
        emit LootWithdrawal(entireBalance, to);
    }
}