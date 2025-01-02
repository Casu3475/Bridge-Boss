// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L1Token is ERC20 {
    uint256 private constant INITIAL_SUPPLY = 1_000_000; // variable defining the initial token supply as 1,000,000 units. It's a good practice to use constants for fixed values like initial supply.

    constructor() ERC20("BossBridgeToken", "BBT") { 
        _mint(msg.sender, INITIAL_SUPPLY * 10 ** decimals()); 
        // Mints the initial supply of tokens and assigns them to the deployer's address. 
        // The 10 ** decimals() part adjusts the supply to account for the token's decimal places (18 by default).
}

