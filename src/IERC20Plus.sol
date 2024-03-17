// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 

interface IERC20Plus is IERC20 {
    function burnFrom(address account, uint256 value) external;
    function mint(address to, uint256 value) external;
}