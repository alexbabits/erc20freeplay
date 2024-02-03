// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Deferred} from "./ERC20Deferred.sol";

contract MockDeferredToken is ERC20Deferred {
    address private immutable ADMIN;

    constructor(uint256 initialSupply) ERC20("MockDeferred", "DERC20") {
        ADMIN = msg.sender;
        _mint(ADMIN, initialSupply);
    }

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}