// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {IERC20Plus} from "./IERC20Plus.sol";

contract Transmuter {
    using SafeERC20 for IERC20;

    address private immutable NORMAL_TOKEN;
    address private immutable FP_TOKEN;

    event Wrap(address indexed caller, address indexed recipient, uint256 indexed amount);
    event Unwrap(address indexed caller, uint256 indexed amount);

    // Example: NORMAL_TOKEN = LINK address. FP_TOKEN = fpLINK address.
    constructor(address normalToken, address fpToken) {
        NORMAL_TOKEN = normalToken;
        FP_TOKEN = fpToken;
    }

    function wrap(uint256 amount, address recipient) external {
        IERC20(NORMAL_TOKEN).safeTransferFrom(msg.sender, address(this), amount);
        IERC20Plus(FP_TOKEN).transmuterMint(recipient, amount);
        emit Wrap(msg.sender, recipient, amount);
    }

    function unwrap(uint256 amount) external {
        IERC20Plus(FP_TOKEN).burnFrom(msg.sender, amount);
        IERC20(NORMAL_TOKEN).safeTransfer(msg.sender, amount);
        emit Unwrap(msg.sender, amount);
    }
}