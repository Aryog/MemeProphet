
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/MemeMelee.sol";
import "./mocks/MockERC20.sol";

contract MemeMeleeTest is Test {
    MemeMelee memeMelee;
    MockERC20 grassToken;
    address owner;
    address user1;
    address user2;
    bytes32 memeHash;

    function setUp() public {
        owner = address(this);
        user1 = address(1);
        user2 = address(2);

        // Deploy mock GRASS token
        grassToken = new MockERC20("GrassToken", "GRASS", 1_000_000 ether);
        
        // Mint tokens to test users
        grassToken.mint(user1, 1_000 ether);
        grassToken.mint(user2, 1_000 ether);

        // Deploy MemeMelee contract
        memeMelee = new MemeMelee(address(grassToken));

        // Add a meme
        memeHash = keccak256(abi.encodePacked("MemeA"));
        memeMelee.addMeme("MemeA", 100);
    }

    function testPickMeme() public {
        // User 1 approves and picks a meme
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), 500 ether);
        memeMelee.pickMeme(memeHash, 500 ether);
        vm.stopPrank();

        // Assert state
        (string memory name, uint256 totalWagered, uint256 pickCount, uint256 openPrice, ) = memeMelee.getMemeDetails(memeHash);
        assertEq(name, "MemeA");
        assertEq(totalWagered, 500 ether);
        assertEq(pickCount, 1);
        assertEq(openPrice, 100);
    }

    function testEndRound() public {
        // User 1 and User 2 pick the meme
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), 500 ether);
        memeMelee.pickMeme(memeHash, 500 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        grassToken.approve(address(memeMelee), 300 ether);
        memeMelee.pickMeme(memeHash, 300 ether);
        vm.stopPrank();

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);

        // End the round
        memeMelee.endRound(memeHash);

        // Verify rewards
        uint256 user1Reward = memeMelee.userRewards(user1);
        uint256 user2Reward = memeMelee.userRewards(user2);

        // Total rewards after fee deduction (5% fee)
        uint256 totalRewardPool = (800 ether * 95) / 100;
        assertEq(user1Reward, (500 ether * totalRewardPool) / 800 ether);
        assertEq(user2Reward, (300 ether * totalRewardPool) / 800 ether);
    }

    function testClaimReward() public {
        // User 1 picks and wins
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), 500 ether);
        memeMelee.pickMeme(memeHash, 500 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        memeMelee.endRound(memeHash);

        // Claim reward
        vm.startPrank(user1);
        uint256 initialBalance = grassToken.balanceOf(user1);
        memeMelee.claimReward();
        uint256 finalBalance = grassToken.balanceOf(user1);
        vm.stopPrank();

        // Assert balance update
        uint256 reward = (500 ether * (800 ether * 95) / 100) / 800 ether;
        assertEq(finalBalance, initialBalance + reward);
    }

    function testAddMeme() public {
        // Add a new meme
        bytes32 newMemeHash = keccak256(abi.encodePacked("MemeB"));
        memeMelee.addMeme("MemeB", 200);

        // Assert state
        (string memory name, , , uint256 openPrice, ) = memeMelee.getMemeDetails(newMemeHash);
        assertEq(name, "MemeB");
        assertEq(openPrice, 200);
    }
}

