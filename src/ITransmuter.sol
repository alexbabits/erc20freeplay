// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ITransmuter {
    function wrap(uint256 amount, address recipient) external;
    function unwrap(uint256 amount) external;
}