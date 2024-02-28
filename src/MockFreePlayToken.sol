// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20FreePlay} from "./ERC20FreePlay.sol";

contract MockFreePlayToken is ERC20FreePlay {
    address private immutable ADMIN;

    constructor(uint256 initialSupply, address _escrow, address _loot) ERC20("MockFreePlay", "FPERC20") {
        ADMIN = msg.sender;
        _mint(ADMIN, initialSupply);
        _setEscrow(_escrow);
        _setLoot(_loot);
        globalTierInfo[Tier.One] = GlobalTierInfo(9500, 0);
        globalTierInfo[Tier.Two] = GlobalTierInfo(9800, 50e18);
        globalTierInfo[Tier.Three] = GlobalTierInfo(9900, 200e18);
        globalTierInfo[Tier.Four] = GlobalTierInfo(9950, 500e18);
        globalTierInfo[Tier.Five] = GlobalTierInfo(9980, 1000e18);
        globalTierInfo[Tier.Six] = GlobalTierInfo(9990, 5000e18);
    }

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}