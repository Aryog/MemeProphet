// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/MemeMeleeFactory.sol";
import "../src/MemeMelee.sol";
import "./mocks/MockERC20.sol";

contract MemeMeleeFactoryTest is Test {
    MemeMeleeFactory factory;
    address grassToken;

    function setUp() public {
        // Deploy a mock ERC20 token as the GRASS token
        grassToken = address(new MockERC20("Grass Token", "GRASS", 18));
        
        // Deploy the MemeMeleeFactory
        factory = new MemeMeleeFactory();
    }

    function testCreateGame() public {
        // Call the createGame function
        factory.createGame(grassToken);

        // Verify the number of deployed games
        address[] memory deployedGames = factory.getDeployedGames();
        assertEq(deployedGames.length, 1);

        // Verify the deployed game address
        address deployedGame = deployedGames[0];
        assertTrue(deployedGame != address(0));

        // Check that the game is an instance of MemeMelee
        MemeMelee memeGame = MemeMelee(deployedGame);
        IERC20 token = memeGame.grassToken(); // Retrieve the grassToken
        assertEq(address(token), grassToken);
    }

    function testMultipleGames() public {
        // Deploy multiple games
        factory.createGame(grassToken);
        factory.createGame(grassToken);

        // Verify the number of deployed games
        address[] memory deployedGames = factory.getDeployedGames();
        assertEq(deployedGames.length, 2);
    }

    function testDeployedGameFunctionality() public {
        // Create a game
        factory.createGame(grassToken);
        address deployedGame = factory.getDeployedGames()[0];

        // Interact with the deployed game
        MemeMelee memeGame = MemeMelee(deployedGame);
        vm.prank(address(1));
        memeGame.addMeme("Test Meme", 100);

        // Verify the meme details
        (string memory name, , , uint256 openPrice, ) = memeGame.getMemeDetails(keccak256(abi.encodePacked("Test Meme")));
        assertEq(name, "Test Meme");
        assertEq(openPrice, 100);
    }
}
