// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/MemeMelee.sol";

// Mock ERC20 token for testing
contract MockPERL is ERC20 {
    constructor() ERC20("MockPERL", "MPERL") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MemeMeleeTest is Test {
    MemeMelee public memeMelee;
    MockPERL public perlToken;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy mock PERL token
        perlToken = new MockPERL();

        // Mint tokens to users
        perlToken.mint(user1, 10_000 * 10**18);
        perlToken.mint(user2, 10_000 * 10**18);

        // Deploy MemeMelee contract
        memeMelee = new MemeMelee(address(perlToken), 1 weeks);

        // Approve the contract to spend tokens
        vm.prank(user1);
        perlToken.approve(address(memeMelee), type(uint256).max);

        vm.prank(user2);
        perlToken.approve(address(memeMelee), type(uint256).max);

        // Add some memes
        memeMelee.addMeme("Doge");
        memeMelee.addMeme("Pepe");
    }

    function testPickMeme() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));
        
        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        (string memory name, uint256 totalWagered, uint256 pickCount) = memeMelee.memes(dogeHash);
        assertEq(name, "Doge");
        assertEq(totalWagered, 1000 * 10**18);
        assertEq(pickCount, 1);
        assertEq(memeMelee.prizePool(), 1000 * 10**18);
    }

    function testCannotPickMemeMultipleTimes() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));
        
        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        vm.prank(user1);
        vm.expectRevert("You have already picked");
        memeMelee.pickMeme(dogeHash, 500 * 10**18);
    }

    function testEndRound() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));
        bytes32 pepeHash = keccak256(abi.encodePacked("Pepe"));

        // Users pick memes
        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        vm.prank(user2);
        memeMelee.pickMeme(pepeHash, 500 * 10**18);

        // Move time forward
        vm.warp(block.timestamp + 1 weeks + 1);

        // End round with Doge as winner
        memeMelee.endRound(dogeHash);

        // Check that contract balance is withdrawn
        assertEq(perlToken.balanceOf(address(memeMelee)), 0);
        assertEq(memeMelee.prizePool(), 0);
    }

    function testSetFeePercent() public {
        memeMelee.setFeePercent(8);
        assertEq(memeMelee.feePercent(), 8);

        vm.expectRevert("Fee percentage too high");
        memeMelee.setFeePercent(15);
    }

    function testAddMeme() public {
        bytes32 newMemeHash = keccak256(abi.encodePacked("Nyan Cat"));
        memeMelee.addMeme("Nyan Cat");

        (string memory name,, ) = memeMelee.memes(newMemeHash);
        assertEq(name, "Nyan Cat");

        vm.expectRevert("Meme already exists");
        memeMelee.addMeme("Nyan Cat");
    }

    function testWithdrawFees() public {
        bytes32 dogeHash = keccak256(abi.encodePacked("Doge"));

        vm.prank(user1);
        memeMelee.pickMeme(dogeHash, 1000 * 10**18);

        // Move time forward
        vm.warp(block.timestamp + 1 weeks + 1);

        // End round with Doge as winner
        memeMelee.endRound(dogeHash);

        // Fees withdrawn during endRound, so this should revert
        vm.expectRevert("Withdrawal failed");
        memeMelee.withdrawFees();
    }
}
