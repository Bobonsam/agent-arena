// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Agent Arena — a daily game for Agent ID holders on BNB Chain
/// @notice Players check in daily to build streaks and earn points, and answer
///         a daily prediction mission. Every core action requires holding an
///         Agent ID (the non-transferable ERC-721 identity of an Agentic Wallet).
/// @dev    Points are an in-game score only. They are NOT a token, cannot be
///         transferred, and have no monetary value. The contract never takes
///         custody of user assets and has no function to move user funds.
///         Owner powers are limited to: publishing future missions, resolving
///         past missions, and an emergency pause. The owner CANNOT change any
///         player's points, streak, or predictions.

interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

contract AgentArena {
    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------
    /// The Agent ID contract. On BNB Chain mainnet this is
    /// 0x60b9262456de011f7d15a54cdd8c48baaa8b022f (SPACE ID Agent ID).
    /// It is fixed at deployment time and can never be changed.
    IAgentID public immutable AGENT_ID;

    uint64 public constant POINTS_CHECKIN = 10;
    uint64 public constant STREAK_BONUS_CAP = 20;
    uint64 public constant POINTS_PREDICTION = 50;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    address public owner;
    bool public paused;

    struct Player {
        uint32 lastCheckinDay;
        uint32 streak;
        uint32 bestStreak;
        uint64 points;
        bool registered;
    }

    struct Mission {
        string question;
        string options; // options separated by ";"
        uint8 optionCount;
        uint8 correctOption; // 0 = not resolved yet, 1..optionCount = answer
        bool exists;
    }

    mapping(address => Player) public players;
    address[] public playerList;

    mapping(uint256 => Mission) public missions;
    /// day => player => chosen option (0 = no prediction)
    mapping(uint256 => mapping(address => uint8)) public predictions;
    /// day => player => prediction points already claimed
    mapping(uint256 => mapping(address => bool)) public predictionClaimed;

    uint256 public totalCheckins;
    uint256 public totalPredictions;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event CheckedIn(address indexed user, uint256 indexed day, uint32 streak, uint64 pointsAwarded);
    event MissionSet(uint256 indexed day, string question, uint8 optionCount);
    event Predicted(address indexed user, uint256 indexed day, uint8 choice);
    event MissionResolved(uint256 indexed day, uint8 correctOption);
    event PredictionClaimed(address indexed user, uint256 indexed day, uint64 pointsAwarded);
    event PausedChanged(bool paused);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    modifier onlyAgent() {
        require(AGENT_ID.balanceOf(msg.sender) > 0, "Agent ID required");
        _;
    }

    constructor(address agentId, address owner_) {
        require(agentId != address(0), "zero address");
        require(owner_ != address(0), "zero owner");
        AGENT_ID = IAgentID(agentId);
        owner = owner_;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function today() public view returns (uint256) {
        return block.timestamp / 86400;
    }

    // ------------------------------------------------------------------
    // Core game actions (Agent ID holders only)
    // ------------------------------------------------------------------
    /// @notice Daily check-in: +10 points plus a streak bonus of
    ///         +1 per streak day beyond the first, capped at +20.
    function checkIn() external whenNotPaused onlyAgent {
        uint256 day = today();
        Player storage p = players[msg.sender];
        require(p.lastCheckinDay < day, "already checked in today");

        if (!p.registered) {
            p.registered = true;
            playerList.push(msg.sender);
        }

        if (p.lastCheckinDay == day - 1) {
            p.streak += 1;
        } else {
            p.streak = 1;
        }
        if (p.streak > p.bestStreak) p.bestStreak = p.streak;
        p.lastCheckinDay = uint32(day);

        uint64 bonus = p.streak - 1;
        if (bonus > STREAK_BONUS_CAP) bonus = STREAK_BONUS_CAP;
        uint64 awarded = POINTS_CHECKIN + bonus;
        p.points += awarded;
        totalCheckins += 1;

        emit CheckedIn(msg.sender, day, p.streak, awarded);
    }

    /// @notice Predict today's mission outcome. One prediction per day.
    function predict(uint8 choice) external whenNotPaused onlyAgent {
        uint256 day = today();
        Mission storage m = missions[day];
        require(m.exists, "no mission today");
        require(m.correctOption == 0, "mission already resolved");
        require(choice >= 1 && choice <= m.optionCount, "invalid choice");
        require(predictions[day][msg.sender] == 0, "already predicted");

        predictions[day][msg.sender] = choice;
        totalPredictions += 1;
        emit Predicted(msg.sender, day, choice);
    }

    /// @notice Claim +50 points for a correct prediction on a resolved day.
    function claimPrediction(uint256 day) external whenNotPaused onlyAgent {
        Mission storage m = missions[day];
        require(m.exists, "no such mission");
        require(m.correctOption != 0, "not resolved yet");
        require(!predictionClaimed[day][msg.sender], "already claimed");
        require(predictions[day][msg.sender] == m.correctOption, "prediction was wrong");

        predictionClaimed[day][msg.sender] = true;
        players[msg.sender].points += POINTS_PREDICTION;
        emit PredictionClaimed(msg.sender, day, POINTS_PREDICTION);
    }

    // ------------------------------------------------------------------
    // Owner: mission management (documented, limited powers)
    // ------------------------------------------------------------------
    /// @notice Publish the mission for a future day. Cannot overwrite.
    function setMission(
        uint256 day,
        string calldata question,
        string calldata options,
        uint8 optionCount
    ) external onlyOwner {
        require(day > today(), "mission day must be in the future");
        require(!missions[day].exists, "mission already set");
        require(optionCount >= 2 && optionCount <= 5, "need 2-5 options");
        require(bytes(question).length > 0 && bytes(question).length <= 280, "bad question length");

        missions[day] = Mission({
            question: question,
            options: options,
            optionCount: optionCount,
            correctOption: 0,
            exists: true
        });
        emit MissionSet(day, question, optionCount);
    }

    /// @notice Resolve a past (or today's) mission with the correct option.
    ///         A resolved mission can never be re-resolved.
    function resolveMission(uint256 day, uint8 correctOption) external onlyOwner {
        Mission storage m = missions[day];
        require(m.exists, "no such mission");
        require(day <= today(), "cannot resolve a future mission");
        require(m.correctOption == 0, "already resolved");
        require(correctOption >= 1 && correctOption <= m.optionCount, "invalid option");

        m.correctOption = correctOption;
        emit MissionResolved(day, correctOption);
    }

    /// @notice Emergency pause. While paused, no game actions are possible.
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedChanged(_paused);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------
    /// @notice Streak tier: 0 = none, 1 = Bronze (3+), 2 = Silver (7+), 3 = Gold (14+)
    function tierOf(address user) public view returns (uint8) {
        uint32 s = players[user].streak;
        if (s >= 14) return 3;
        if (s >= 7) return 2;
        if (s >= 3) return 1;
        return 0;
    }

    function getPlayer(address user)
        external
        view
        returns (
            uint32 lastCheckinDay,
            uint32 streak,
            uint32 bestStreak,
            uint64 points,
            uint8 tier,
            bool registered
        )
    {
        Player storage p = players[user];
        return (p.lastCheckinDay, p.streak, p.bestStreak, p.points, tierOf(user), p.registered);
    }

    function getMission(uint256 day)
        external
        view
        returns (
            string memory question,
            string memory options,
            uint8 optionCount,
            uint8 correctOption,
            bool exists
        )
    {
        Mission storage m = missions[day];
        return (m.question, m.options, m.optionCount, m.correctOption, m.exists);
    }

    function playerCount() external view returns (uint256) {
        return playerList.length;
    }

    function playersPage(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory page)
    {
        uint256 n = playerList.length;
        if (offset >= n) return new address[](0);
        uint256 end = offset + limit;
        if (end > n) end = n;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = playerList[i];
        }
    }
}
