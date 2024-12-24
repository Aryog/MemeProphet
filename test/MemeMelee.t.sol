// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MemeMelee.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock GRASS Token for testing
contract MockGrassToken is ERC20 {
    constructor() ERC20("GRASS Token", "GRASS") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract MemeMeleeTest is Test {
    MemeMelee public memeMelee;
    MockGrassToken public grassToken;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    uint256 public constant MINIMUM_WAGER = 1e15; // 0.001 GRASS
    bytes32 public meme1Hash;
    bytes32 public meme2Hash;

    event MemePicked(address indexed user, bytes32 memeHash, uint256 amount);
    event RoundEnded(bytes32 winningMeme, uint256 prizeDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event NewRoundStarted(uint256 indexed roundNumber, uint256 startTime, uint256 endTime);

    function setUp() public {
        // Setup accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy contracts
        grassToken = new MockGrassToken();
        memeMelee = new MemeMelee(address(grassToken));

        // Fund test accounts
        uint256 initialBalance = 1000 * 10**18;
        grassToken.transfer(user1, initialBalance);
        grassToken.transfer(user2, initialBalance);
        grassToken.transfer(user3, initialBalance);

        // Add initial memes
        memeMelee.addMeme("Doge", 100);
        memeMelee.addMeme("Pepe", 200);
        
        meme1Hash = keccak256(abi.encodePacked("Doge"));
        meme2Hash = keccak256(abi.encodePacked("Pepe"));
    }

    function testInitialState() public {
        assertTrue(memeMelee.roundActive());
        assertEq(memeMelee.currentRound(), 1);
        assertTrue(memeMelee.roundEndTime() > block.timestamp);
    }

    function testAddMeme() public {
        string memory newMemeName = "Wojak";
        bytes32 newMemeHash = keccak256(abi.encodePacked(newMemeName));
        
        memeMelee.addMeme(newMemeName, 150);
        
        (string memory name,,,,) = memeMelee.getMemeDetails(newMemeHash);
        assertEq(name, newMemeName);
    }

    function testCannotAddDuplicateMeme() public {
        vm.expectRevert("Meme already exists");
        memeMelee.addMeme("Doge", 100);
    }

    function testPickMeme() public {
        uint256 wagerAmount = MINIMUM_WAGER;
        
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount);
        
        vm.expectEmit(true, true, true, true);
        emit MemePicked(user1, meme1Hash, wagerAmount);
        
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        vm.stopPrank();
        
        (,uint256 totalWagered, uint256 pickCount,,) = memeMelee.getMemeDetails(meme1Hash);
        assertEq(totalWagered, wagerAmount);
        assertEq(pickCount, 1);
    }

    function testCannotPickTwice() public {
        uint256 wagerAmount = MINIMUM_WAGER;
        
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount * 2);
        
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        
        vm.expectRevert("Already picked this round");
        memeMelee.pickMeme(meme2Hash, wagerAmount);
        vm.stopPrank();
    }

    function testCannotPickWithInsufficientWager() public {
        uint256 wagerAmount = MINIMUM_WAGER - 1;
        
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount);
        
        vm.expectRevert("Minimum wager is 0.001 GRASS");
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        vm.stopPrank();
    }

    function testEndRound() public {
        // Setup picks
        uint256 wagerAmount = MINIMUM_WAGER;
        
        // User1 picks meme1
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount);
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        vm.stopPrank();
        
        // User2 picks meme1
        vm.startPrank(user2);
        grassToken.approve(address(memeMelee), wagerAmount);
        memeMelee.pickMeme(meme2Hash, wagerAmount);
        vm.stopPrank();
        
        // Advance time to end of round
        vm.warp(block.timestamp + 1 days);
        
        // End round with meme1 as winner
        vm.expectEmit(true, true, true, true);
        emit RoundEnded(meme1Hash, (wagerAmount * 2 * 95) / 100); // 95% of total pool (5% fee)
        
        memeMelee.endRound(meme1Hash);
        
        // Check new round started
        assertTrue(memeMelee.roundActive());
        assertEq(memeMelee.currentRound(), 2);
    }

    function testCannotEndRoundEarly() public {
        vm.expectRevert("Round still ongoing");
        memeMelee.endRound(meme1Hash);
    }

    function testClaimRewards() public {
        // Setup picks
        uint256 wagerAmount = MINIMUM_WAGER;
        
        // User1 picks winning meme
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount);
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        vm.stopPrank();
        
        // Advance time and end round
        vm.warp(block.timestamp + 1 days);
        memeMelee.endRound(meme1Hash);
        
        // Claim rewards
        uint256 initialBalance = grassToken.balanceOf(user1);
        
        vm.prank(user1);
        memeMelee.claimReward();
        
        uint256 finalBalance = grassToken.balanceOf(user1);
        assertTrue(finalBalance > initialBalance);
    }

    function testNewRoundReset() public {
        // Make picks in first round
        uint256 wagerAmount = MINIMUM_WAGER;
        
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount);
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        vm.stopPrank();
        
        // End first round
        vm.warp(block.timestamp + 1 days);
        memeMelee.endRound(meme1Hash);
        
        // Verify reset
        (,uint256 totalWagered, uint256 pickCount,,) = memeMelee.getMemeDetails(meme1Hash);
        assertEq(totalWagered, 0);
        assertEq(pickCount, 0);
        
        // Verify can pick in new round
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount);
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        vm.stopPrank();
    }

    function testFuzz_PickMeme(uint256 wagerAmount) public {
        // Bound wager amount between minimum and user balance
        wagerAmount = bound(wagerAmount, MINIMUM_WAGER, grassToken.balanceOf(user1));
        
        vm.startPrank(user1);
        grassToken.approve(address(memeMelee), wagerAmount);
        memeMelee.pickMeme(meme1Hash, wagerAmount);
        vm.stopPrank();
        
        (,uint256 totalWagered, uint256 pickCount,,) = memeMelee.getMemeDetails(meme1Hash);
        assertEq(totalWagered, wagerAmount);
        assertEq(pickCount, 1);
    }

    receive() external payable {}
}
