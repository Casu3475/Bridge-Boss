// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/* 
* @title TokenFactory
* @dev Allows the owner to deploy new ERC20 contracts
* @dev This contract will be deployed on both an L1 & an L2
*/
contract TokenFactory is Ownable {
    mapping(string tokenSymbol => address tokenAddress) private s_tokenToAddress;

    event TokenDeployed(string symbol, address addr);

    constructor() Ownable(msg.sender) { }

    /*
     * @dev Deploys a new ERC20 contract
     * @param symbol The symbol of the new token
     * @param contractBytecode The bytecode of the new token
     */
    function deployToken(string memory symbol, bytes memory contractBytecode) public onlyOwner returns (address addr) {
        //q are you sure you want thos out of scope ???
        assembly { // writing code directly in the EVM low-level language called Yul (or "inline assembly").
            addr := create(0, add(contractBytecode, 0x20), mload(contractBytecode)) // opcode !
            // create(value, offset, size) → address
            // Deploys the contract with value: 0 (no Ether sent). offset: The start of the actual bytecode in memory. size: The size of the bytecode.
        }   // To get the actual bytecode, we skip the first 32 bytes by adding 0x20 (32 in decimal) to the memory pointer.
        s_tokenToAddress[symbol] = addr;
        emit TokenDeployed(symbol, addr);
    }

    function getTokenAddressFromSymbol(string memory symbol) public view returns (address addr) {
        return s_tokenToAddress[symbol];
    }
}
