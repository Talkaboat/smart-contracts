pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../interfaces/IMasterEntertainer.sol";

contract EarlyAdopterPool is ReentrancyGuard, IMasterEntertainer {
    using SafeMath for uint256; 
    using SafeERC20 for IERC20;
    using Address for address;    
    struct UserInfo {
        uint256 amount;     // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt for this user, used to calculate the reward amount.
        uint256 lastClaim;  // Timestamp of the last time the user claimed rewards.
    }

    address public owner;        // Owner of the staking pool.
    IERC20 public token;         // Token being staked.
    uint256 public totalStaked;  // Total amount of tokens staked.
    uint256 public totalRewards; // Total amount of rewards earned.

    uint256 public unlockPeriod; // Time it takes for a user to unlock 25% of their initial deposit.
    uint256 public unlockPercent = 25; // Percent of initial deposit unlocked per month.

    uint256 public startTimestamp; // Timestamp when staking started.

    uint256 public tokensPerBlock; // Tokens rewarded per block
    uint256 public totalBlocks; // Total blocks to distribute rewards

    mapping(address => UserInfo) public userInfo; // Mapping of user addresses to their UserInfo struct.

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    constructor(IERC20 _token, uint256 _unlockPeriod) {
        owner = msg.sender;
        token = _token;
        unlockPeriod = _unlockPeriod;
        startTimestamp = block.timestamp.add(_unlockPeriod * 1 minutes);

        totalRewards = 1e27; // 1 billion tokens with 18 decimals
        uint256 secondsInThreeMonths = uint256(1 * 90 days).div(1 seconds);
        uint256 averageBlockTime = 3; // Average block time in seconds
        totalBlocks = secondsInThreeMonths.div(averageBlockTime);
        tokensPerBlock = totalRewards.div(totalBlocks);
    }

    function emergencyWithdraw() external {
        require(msg.sender == owner, "Only the owner can deposit tokens");
        uint256 coinBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, coinBalance);

    }

    function deposit(address[] calldata _users, uint256[] calldata _amounts) external {
        require(msg.sender == owner, "Only the owner can deposit tokens");
        require(_users.length == _amounts.length, "Address and amount arrays must have same length");

        for(uint256 i = 0; i < _amounts.length; i++) {
            totalStaked = totalStaked.add(_amounts[i]);
        }

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            uint256 amount = _amounts[i];

            require(amount > 0, "Amount must be greater than zero");

            userInfo[user].amount = userInfo[user].amount.add(amount);
            userInfo[user].rewardDebt = 0;

            emit Deposit(user, amount);
        }
        
        token.safeTransferFrom(address(msg.sender), address(this), totalStaked);
    }

    function getBalanceOf(address _user, uint256 _vesting) external override view returns (uint256) {
        return userInfo[_user].amount;
    }

    function depositForUser(uint256 _pid, uint256 _amount, address user) external override nonReentrant {
    }

    function updatePrice() override external {
    }

    function withdraw(uint256 _amount) external {
        UserInfo storage userStaking = userInfo[msg.sender];

        require(userStaking.amount >= _amount, "Insufficient balance");
        require(block.timestamp >= startTimestamp.add(unlockPeriod), "Tokens cannot be withdrawn yet");

        uint256 unlocked = _calculateUnlockedAmount(msg.sender);

        require(_amount <= unlocked, "Amount exceeds unlocked balance");

        userStaking.amount = userStaking.amount.sub(_amount);
        totalStaked = totalStaked.sub(_amount);

        token.transfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function claim() external nonReentrant {
        UserInfo storage userStaking = userInfo[msg.sender];

        uint256 pending = _calculatePendingRewards(msg.sender);

        require(pending > 0, "No rewards to claim");
        uint256 coinBalance = token.balanceOf(address(this)).sub(totalStaked);
        if(pending > coinBalance) {
            pending = coinBalance;
        }
        userStaking.rewardDebt = userStaking.rewardDebt.add(pending);
        userStaking.lastClaim = block.timestamp;

        totalRewards = totalRewards.sub(pending);

        token.safeTransfer(msg.sender, pending);
        emit Claim(msg.sender, pending);
    }

    function _calculateUnlockedAmount(address _user) internal view returns (uint256) {
        if (block.timestamp < startTimestamp) {
            return 0;
        }
        uint256 daysPerMonth = 2;
        uint256 daysElapsed = block.timestamp.sub(startTimestamp).div(1 minutes);
        uint256 monthsElapsed = daysElapsed.div(daysPerMonth);

        uint256 unlockedPercentage = 25;
        if(daysElapsed > daysPerMonth && monthsElapsed > 0 && monthsElapsed < 3) {
            unlockedPercentage = unlockedPercentage.add(uint256(25).mul(monthsElapsed));
        } else if(monthsElapsed > 3) {
            unlockedPercentage = 100;
        }
        uint256 unlockedAmount = userInfo[_user].amount.mul(unlockedPercentage).div(100);

        return unlockedAmount;
    }

    function pendingCoin(address _user) external view returns (uint256) {
        return _calculatePendingRewards(_user);
    }

    function _calculatePendingRewards(address _user) internal view returns (uint256) {
        UserInfo storage userStaking = userInfo[_user];

        uint256 stakedAmount = userStaking.amount;
        uint256 rewardDebt = userStaking.rewardDebt;

        if (block.timestamp <= startTimestamp) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp.sub(startTimestamp);
        uint256 estimatedBlocks = timeElapsed.div(3);
        uint256 blockReward = estimatedBlocks.mul(tokensPerBlock);

        uint256 pendingReward = stakedAmount.mul(blockReward).div(totalStaked).sub(rewardDebt);

        uint256 coinBalance = token.balanceOf(address(this)).sub(totalStaked);
        if(pendingReward > coinBalance) {
            pendingReward = coinBalance;
        }
        return pendingReward;
    }
}