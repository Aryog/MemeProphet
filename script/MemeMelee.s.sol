// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/MemeMelee.sol";

contract MemeMeleeDeployScript is Script {
    function run() public {
        // Retrieve private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Grass token address from Lens Protocol
        address grassTokenAddress = vm.envAddress("GRASS_TOKEN_ADDRESS");

        // Start broadcast with the deployer's private key
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the MemeMelee contract
        MemeMelee memeMelee = new MemeMelee(grassTokenAddress);

        // Stop broadcasting
        vm.stopBroadcast();

        // Log the deployed contract address
        console.log("MemeMelee Contract Deployed at:", address(memeMelee));
    }
}
