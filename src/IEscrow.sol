// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEscrow {
    function transferUnderlyingTokensBasedOnResult(address user, uint256 value, uint8 result) external;
    function transferUnderlyingTokens(address to, uint256 value) external;
}