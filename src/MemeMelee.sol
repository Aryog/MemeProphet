// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MemeMelee is Ownable {
    using ECDSA for bytes32;

    struct Meme {
        string name;
        uint256 totalWagered;
        uint256 pickCount;
    }

    IERC20 public perlToken;
    uint256 public feePercent = 5; // Fee percentage (e.g., 5%)
    uint256 public roundEndTime;
    uint256 public prizePool;

    mapping(bytes32 => Meme) public memes; // Memes indexed by their hash
    mapping(address => bool) private hasPicked; // To track if a user has participated

    event MemePicked(address indexed user, bytes32 memeHash, uint256 amount);
    event RoundEnded(bytes32 winningMeme, uint256 prizeDistributed);

    constructor(address _perlToken, uint256 _roundDuration) Ownable(msg.sender) {
        perlToken = IERC20(_perlToken);
        roundEndTime = block.timestamp + _roundDuration;
    }

    modifier onlyBeforeEnd() {
        require(block.timestamp < roundEndTime, "Round has ended");
        _;
    }

    function pickMeme(bytes32 memeHash, uint256 amount) external onlyBeforeEnd {
        require(!hasPicked[msg.sender], "You have already picked");
        require(amount > 0, "Amount must be greater than zero");
        
        // Transfer PERL tokens from the user to the contract
        require(perlToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        Meme storage meme = memes[memeHash];
        meme.totalWagered += amount;
        meme.pickCount++;
        prizePool += amount;
        hasPicked[msg.sender] = true;
        
        emit MemePicked(msg.sender, memeHash, amount);
    }

    function endRound(bytes32 winningMeme) external onlyOwner {
        require(block.timestamp >= roundEndTime, "Round is still ongoing");
        
        Meme memory winner = memes[winningMeme];
        require(winner.pickCount > 0, "No picks for the winning meme");
        
        // Withdraw all contract funds to owner before distributing rewards
        uint256 totalContractBalance = perlToken.balanceOf(address(this));
        if (totalContractBalance > 0) {
            require(perlToken.transfer(owner(), totalContractBalance), "Withdrawal failed");
        }
        
        uint256 fee = (prizePool * feePercent) / 100;
        uint256 rewardPool = prizePool - fee;
        
        // Reset state for the next round
        prizePool = 0;
        roundEndTime = block.timestamp + (roundEndTime - block.timestamp);
        
        emit RoundEnded(winningMeme, rewardPool);
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 10, "Fee percentage too high");
        feePercent = _feePercent;
    }

    function addMeme(string memory name) external onlyOwner {
        bytes32 memeHash = keccak256(abi.encodePacked(name));
        require(memes[memeHash].pickCount == 0, "Meme already exists");
        memes[memeHash] = Meme(name, 0, 0);
    }

    function withdrawFees() external onlyOwner {
        uint256 feeBalance = (prizePool * feePercent) / 100;
        require(perlToken.transfer(owner(), feeBalance), "Withdrawal failed");
    }
}
