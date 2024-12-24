// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MemeMelee is Ownable {
    using ECDSA for bytes32;

    struct Meme {
        string name;
        uint256 totalWagered;
        uint256 pickCount;
        bool exists;
        uint256 openPrice;
        uint256 closePrice;
        mapping(address => uint256) userWagers;
        address[] userList; // Array to track users who wagered
    }

    IERC20 public grassToken;
    uint256 public constant ROUND_DURATION = 1 days;
    uint256 public feePercent = 5;
    uint256 public roundEndTime;
    uint256 public prizePool;

    mapping(bytes32 => Meme) public memes;
    mapping(address => bool) private hasPicked;
    mapping(address => uint256) public userRewards;
    bytes32[] public memeHashes;
    
    // Track active round
    uint256 public currentRound;
    bool public roundActive;

    event MemePicked(address indexed user, bytes32 memeHash, uint256 amount);
    event RoundEnded(bytes32 winningMeme, uint256 prizeDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event MemePriceSet(bytes32 indexed memeHash, uint256 openPrice, uint256 closePrice);
    event NewRoundStarted(uint256 indexed roundNumber, uint256 startTime, uint256 endTime);

    constructor(address _grassToken) Ownable(msg.sender) {
        grassToken = IERC20(_grassToken);
        startNewRound();
    }

    function startNewRound() public {
        require(!roundActive || block.timestamp >= roundEndTime, "Current round still active");
        
        roundEndTime = block.timestamp + ROUND_DURATION;
        currentRound++;
        roundActive = true;
        prizePool = 0;

        // Reset all user picks for the new round
        for (uint256 i = 0; i < memeHashes.length; i++) {
            bytes32 memeHash = memeHashes[i];
            Meme storage meme = memes[memeHash];
            
            // Reset meme stats
            meme.totalWagered = 0;
            meme.pickCount = 0;
            
            // Clear user wagers
            for (uint256 j = 0; j < meme.userList.length; j++) {
                address user = meme.userList[j];
                delete meme.userWagers[user];
                delete hasPicked[user]; // Reset user picks for new round
            }
            delete meme.userList;
        }

        emit NewRoundStarted(currentRound, block.timestamp, roundEndTime);
    }

    modifier onlyDuringRound() {
        require(roundActive, "No active round");
        require(block.timestamp < roundEndTime, "Round has ended");
        _;
    }

    function pickMeme(bytes32 memeHash, uint256 amount) external onlyDuringRound {
        require(!hasPicked[msg.sender], "Already picked this round");
        require(amount >= 1e15, "Minimum wager is 0.001 GRASS");
        require(memes[memeHash].exists, "Meme does not exist");

        require(grassToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        Meme storage meme = memes[memeHash];
        meme.totalWagered += amount;
        meme.pickCount++;
        meme.userWagers[msg.sender] = amount;
        meme.userList.push(msg.sender);
        prizePool += amount;
        hasPicked[msg.sender] = true;

        emit MemePicked(msg.sender, memeHash, amount);
    }

    function endRound(bytes32 winningMeme) external onlyOwner {
        require(roundActive, "No active round");
        require(block.timestamp >= roundEndTime, "Round still ongoing");
        require(memes[winningMeme].exists && memes[winningMeme].pickCount > 0, "Invalid winning meme");

        Meme storage winner = memes[winningMeme];
        _setClosePrice(winningMeme);

        uint256 totalBalance = grassToken.balanceOf(address(this));
        require(totalBalance >= prizePool, "Insufficient contract balance");

        uint256 fee = (prizePool * feePercent) / 100;
        uint256 rewardPool = prizePool - fee;

        // Distribute rewards
        for (uint256 i = 0; i < winner.userList.length; i++) {
            address user = winner.userList[i];
            uint256 userWager = winner.userWagers[user];
            if (userWager > 0) {
                uint256 userReward = (userWager * rewardPool) / winner.totalWagered;
                userRewards[user] += userReward; // Fixed: Now properly assigns to user instead of msg.sender
                emit UserRewarded(user, userReward);
            }
        }

        // Transfer fee to owner
        if (fee > 0) {
            require(grassToken.transfer(owner(), fee), "Fee transfer failed");
        }

        roundActive = false;
        emit RoundEnded(winningMeme, rewardPool);
        
        // Start new round automatically
        startNewRound();
    }


    function addMeme(string memory name, uint256 openPrice) external onlyOwner {
        bytes32 memeHash = keccak256(abi.encodePacked(name));
        require(!memes[memeHash].exists, "Meme already exists");

        // Create the Meme without using struct constructor
        Meme storage newMeme = memes[memeHash];
        newMeme.name = name;
        newMeme.totalWagered = 0;
        newMeme.pickCount = 0;
        newMeme.exists = true;

        // Set the opening price
        _setOpenPrice(memeHash, openPrice);

        // Add to meme hashes
        memeHashes.push(memeHash);
    }

    // Internal function to set the opening price if possible do oracle to get the openPrice
    function _setOpenPrice(bytes32 memeHash, uint256 openPrice) internal {
        Meme storage meme = memes[memeHash];
        meme.openPrice = openPrice;
        emit MemePriceSet(memeHash, openPrice, 0);
    }

    // Internal function to set the closing price
    function _setClosePrice(bytes32 memeHash) internal {
        Meme storage meme = memes[memeHash];
        meme.closePrice = uint256(block.timestamp); // Example: Replace this with actual logic to fetch closing price
        emit MemePriceSet(memeHash, meme.openPrice, meme.closePrice);
    }

    // New function to allow users to claim their rewards
    function claimReward() external {
        uint256 reward = userRewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        // Reset user's reward
        userRewards[msg.sender] = 0;

        // Transfer reward to user
        require(grassToken.transfer(msg.sender, reward), "Reward transfer failed");
    }

    // Getter function for meme details
    function getMemeDetails(bytes32 memeHash) external view returns (
        string memory name,
        uint256 totalWagered,
        uint256 pickCount,
        uint256 openPrice,
        uint256 closePrice
    ) {
        Meme storage meme = memes[memeHash];
        return (
            meme.name,
            meme.totalWagered,
            meme.pickCount,
            meme.openPrice,
            meme.closePrice
        );
    }
}

