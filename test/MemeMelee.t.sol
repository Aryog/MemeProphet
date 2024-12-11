// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/MemeMelee.sol";

// Mock ERC20 token for testing
contract MockGRASS is ERC20 {
    constructor() ERC20("MockGRASS", "MGRASS") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MemeMeleeTest is Test {
    MemeMelee public memeMelee;
    MockGRASS public grassToken;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);

        // Deploy mock GRASS token
        grassToken = new MockGRASS();

        // Mint tokens to users
        grassToken.mint(user1, 10_000 * 10**18);
        grassToken.mint(user2, 10_000 * 10**18);
        grassToken.mint(user3, 10_000 * 10**18);

        // Deploy MemeMelee contract
        memeMelee = new MemeMelee(address(grassToken));

        // Approve the contract to spend tokens
        vm.prank(user1);
        grassToken.approve(address(memeMelee), type(uint256).max);

        vm.prank(user2);
        grassToken.approve(address(memeMelee), type(uint256).max);

        vm.prank(user3);
        grassToken.approve(address(memeMelee), type(uint256).max);

        // Add some memes
        memeMelee.addMeme("Doge");
        memeMelee.addMeme("Pepe");
    }

    function testPickMeme() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));
        
        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        (string memory name, uint256 totalWagered, uint256 pickCount, int256 dailyPercentageChange) = memeMelee.getMemeDetails(dogeHash);
        assertEq(name, "Doge");
        assertEq(totalWagered, 1000 * 10**18);
        assertEq(pickCount, 1);
        assertEq(dailyPercentageChange, 0);
        assertEq(memeMelee.prizePool(), 1000 * 10**18);
    }

    function testCannotPickNonExistentMeme() public {
        bytes32 nonExistentHash = keccak256(abi.encodePacked("NonExistent"));
        
        vm.prank(user1);
        vm.expectRevert("Meme does not exist");
        memeMelee.pickMeme(nonExistentHash, 1000 * 10**18);
    }

    function testCannotPickMemeMultipleTimes() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));
        
        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        vm.prank(user1);
        vm.expectRevert("You have already picked");
        memeMelee.pickMeme(dogeHash, 500 * 10**18);
    }

    function testRewardDistribution() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));
        bytes32 pepeHash = keccak256(abi.encodePacked("Pepe"));

        // Users pick memes
        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        vm.prank(user2);
        memeMelee.pickMeme(pepeHash, 500 * 10**18);

        // Mint more tokens to the contract for rewards
        grassToken.mint(address(memeMelee), 10_000 * 10**18);

        // Move time forward
        vm.warp(block.timestamp + 1 weeks + 1);

        // Mint tokens for percentage change update (if needed)
        uint256 user1BalanceBefore = grassToken.balanceOf(user1);
        uint256 user2BalanceBefore = grassToken.balanceOf(user2);

        // Arbitrary percentage change update
        memeMelee.updateDailyPercentageChange(dogeHash, 10);

        // End round with Doge as winner
        memeMelee.endRound(dogeHash);

        // Verify user rewards
        assertGt(memeMelee.userRewards(user1), 0);
        assertEq(memeMelee.userRewards(user2), 0);

        // Claim rewards
        vm.prank(user1);
        memeMelee.claimReward();

        uint256 user1BalanceAfter = grassToken.balanceOf(user1);
        assertTrue(user1BalanceAfter > user1BalanceBefore);
        assertEq(memeMelee.userRewards(user1), 0);
    }

    function testCannotClaimZeroRewards() public {
        vm.prank(user3);
        vm.expectRevert("No rewards to claim");
        memeMelee.claimReward();
    }

    function testAddMeme() public {
        bytes32 newMemeHash = keccak256(abi.encodePacked("Nyan Cat"));
        memeMelee.addMeme("Nyan Cat");

        (string memory name,,, int256 dailyPercentageChange) = memeMelee.getMemeDetails(newMemeHash);
        assertEq(name, "Nyan Cat");

        vm.expectRevert("Meme already exists");
        memeMelee.addMeme("Nyan Cat");
    }

    function testDailyPercentageChangeUpdate() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));
        
        // Update daily percentage change
        memeMelee.updateDailyPercentageChange(dogeHash, 15);

        (,,,int256 dailyPercentageChange) = memeMelee.getMemeDetails(dogeHash);
        assertEq(dailyPercentageChange, 15);
    }

    function testWithdrawFees() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));

        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        uint256 ownerBalanceBefore = grassToken.balanceOf(owner);
        
        // Move time forward
        vm.warp(block.timestamp + 1 weeks + 1);
        memeMelee.endRound(dogeHash);

        uint256 ownerBalanceAfter = grassToken.balanceOf(owner);
        assertTrue(ownerBalanceAfter > ownerBalanceBefore);
    }
}
