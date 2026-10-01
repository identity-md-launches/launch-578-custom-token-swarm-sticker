// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Swarm Sticker (STICK)
/// @notice A fixed-supply community token with no fees or administrative powers.
contract SwarmSticker is ERC20 {
    /// @dev The caller receives all one billion tokens. During an IMD launch this is the factory.
    constructor() ERC20("Swarm Sticker", "STICK") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
