
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./MemeMelee.sol";

contract MemeMeleeFactory {
    address[] public deployedGames;
    event GameCreated(address indexed gameAddress, address creator);

    function createGame(address grassToken) external {
        MemeMelee newGame = new MemeMelee(grassToken);
        deployedGames.push(address(newGame));
        emit GameCreated(address(newGame), msg.sender);
    }

    function getDeployedGames() external view returns (address[] memory) {
        return deployedGames;
    }
}
