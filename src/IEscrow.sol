// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IEscrow {
    function transferUnderlyingTokens(address to, uint256 value) external;
}