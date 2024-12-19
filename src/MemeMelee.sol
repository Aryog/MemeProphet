
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
        bool exists;
        uint256 openPrice;  // New: Opening price
        uint256 closePrice; // New: Closing price
        mapping(address => uint256) userWagers; // Track individual user wagers
    }

    IERC20 public grassToken;
    uint256 public constant ROUND_DURATION = 1 days;
    uint256 public feePercent = 5;
    uint256 public roundEndTime;
    uint256 public prizePool;

    mapping(bytes32 => Meme) public memes;
    mapping(address => bool) private hasPicked;
    bytes32[] public memeHashes;

    // New mapping to store user rewards
    mapping(address => uint256) public userRewards;

    event MemePicked(address indexed user, bytes32 memeHash, uint256 amount);
    event RoundEnded(bytes32 winningMeme, uint256 prizeDistributed);
    event UserRewarded(address indexed user, uint256 amount);
    event MemePriceSet(bytes32 indexed memeHash, uint256 openPrice, uint256 closePrice);

    constructor(address _grassToken) Ownable(msg.sender) {
        grassToken = IERC20(_grassToken);
        roundEndTime = block.timestamp + ROUND_DURATION;
    }

    modifier onlyBeforeEnd() {
        require(block.timestamp < roundEndTime, "Round has ended");
        _;
    }

    

    function pickMeme(bytes32 memeHash, uint256 amount) external onlyBeforeEnd {
        require(!hasPicked[msg.sender], "You have already picked");
        require(amount > 0, "Amount must be greater than zero");
        require(memes[memeHash].exists, "Meme does not exist");

        // Transfer GRASS tokens from the user to the contract
        require(grassToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        Meme storage meme = memes[memeHash];
        meme.totalWagered += amount;
        meme.pickCount++;
        meme.userWagers[msg.sender] = amount; // Track individual user wager
        prizePool += amount;
        hasPicked[msg.sender] = true;

        emit MemePicked(msg.sender, memeHash, amount);
    }

    function endRound(bytes32 winningMeme) external onlyOwner {
        require(block.timestamp >= roundEndTime, "Round is still ongoing");

        Meme storage winner = memes[winningMeme];
        require(winner.exists, "Winning meme does not exist");
        require(winner.pickCount > 0, "No picks for the winning meme");

        // Set the closing price
        _setClosePrice(winningMeme);

        uint256 totalContractBalance = grassToken.balanceOf(address(this));
        uint256 fee = (totalContractBalance * feePercent) / 100;
        uint256 rewardPool = totalContractBalance - fee;

        // Distribute rewards to users who picked the winning meme
        for (uint256 i = 0; i < memeHashes.length; i++) {
            if (memeHashes[i] == winningMeme) {
                Meme storage currentMeme = memes[memeHashes[i]];

                // Iterate through all meme hashes as a proxy for user list
                for (uint256 j = 0; j < memeHashes.length; j++) {
                    bytes32 memeHash = memeHashes[j];
                    address user = address(uint160(uint256(keccak256(abi.encodePacked(memeHash, j)))));

                    // Check if the user wagered on the winning meme
                    uint256 userWager = currentMeme.userWagers[user];
                    if (userWager > 0) {
                        // Calculate user's share of the reward pool
                        uint256 userReward = (userWager * rewardPool) / currentMeme.totalWagered;

                        // Update user rewards
                        userRewards[user] += userReward;
                        emit UserRewarded(user, userReward);
                    }
                }
            }
        }

        // Transfer fee to owner
        if (fee > 0) {
            require(grassToken.transfer(owner(), fee), "Fee transfer failed");
        }

        // Reset state for the next round
        prizePool = 0;
        roundEndTime = block.timestamp + ROUND_DURATION;

        // Reset picking status and wagers
        for (uint256 i = 0; i < memeHashes.length; i++) {
            Meme storage currentMeme = memes[memeHashes[i]];
            currentMeme.pickCount = 0;
            currentMeme.totalWagered = 0;

            // Clear user wagers (this is a limitation with mappings)
            for (uint256 j = 0; j < memeHashes.length; j++) {
                bytes32 memeHash = memeHashes[j];
                address user = address(uint160(uint256(keccak256(abi.encodePacked(memeHash, j)))));
                currentMeme.userWagers[user] = 0;
            }
        }

        emit RoundEnded(winningMeme, rewardPool);
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

