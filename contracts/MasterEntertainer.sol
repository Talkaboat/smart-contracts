// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./TalkaboatToken.sol";
import "./libraries/TransferHelper.sol";

contract MasterEntertainer is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;
    using Address for address;    
    
    /* =====================================================================================================================
                                                        Structs
    ===================================================================================================================== */
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }
    
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accCoinPerShare;
        uint16 depositFee; 
    }
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;
    mapping(IERC20 => bool) public poolExistence;
    
    TalkaboatToken public coin;
    
    PoolInfo[] public poolInfos;
    
    uint256[] public hourlyPrices;
    uint256 public hourlyIndex = 0;
    
    address public devAddress;
    address public feeAddress;
    address public lpAddress;
    
    uint256 public coinPerBlock;
    uint256 public startBlock;
    uint256 public totalAllocPoint = 0;
    uint256 public depositedCoins = 0;
    uint256 public lastEmissionUpdateBlock;
    uint256 public lastPriceUpdateBlock;
    uint256 public lastAveragePrice = 0;
    uint256 public lastEmissionIncrease = 0;
    uint16 public maxEmissionIncrease = 25000;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event NewPool(address indexed pool, uint256 indexed pid);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event SetLpAddress(address indexed user, address indexed newAddress);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event SetMaxEmissionIncrease(address indexed user, uint16 newMaxEmissionIncrease);
    event UpdateEmissionRate(address indexed user, uint256 newEmission);
    
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: lpToken already exists in poolInfos");
        _;
    }
    
    constructor(TalkaboatToken _coin, address _devaddr, address _feeAddress, uint256 _startBlock) {
        coin = _coin;
        devAddress = _devaddr;
        feeAddress = _feeAddress;
        coinPerBlock = 100 ether;
        startBlock = _startBlock;
        lastEmissionUpdateBlock = block.timestamp;
        lastPriceUpdateBlock = block.timestamp;
        add(20, coin, 0, false);
        for(uint8 i = 0; i < 24; i++) {
            hourlyPrices.push(0);
        }
    }  

    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    function setDevAddress(address _devAddress) public onlyOwner {
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }
    
    function massUpdatePools() public {
        uint256 length = poolInfos.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    
    function setPoolVariables(uint256 _pid, uint256 _allocPoint, uint16 _depositFee, bool _withUpdate) public onlyOwner {
        require(_depositFee <= 10000,"set: deposit fee can't exceed 10 %");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfos[_pid].allocPoint).add(_allocPoint);
        poolInfos[_pid].allocPoint = _allocPoint;
        poolInfos[_pid].depositFee = _depositFee;
    }
    
    function updateEmissionRate(uint256 _coinPerBlock) public onlyOwner {
        massUpdatePools();
        coinPerBlock = _coinPerBlock;
        emit UpdateEmissionRate(msg.sender, _coinPerBlock);
    }
    
    function setMaxEmissionIncrease(uint16 _maxEmissionIncrease) public onlyOwner {
        maxEmissionIncrease = _maxEmissionIncrease;
        emit SetMaxEmissionIncrease(msg.sender, _maxEmissionIncrease);
    }
    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    function poolLength() external view returns (uint256) {
        return poolInfos.length;
    }
    
    function canClaimRewards(uint256 _amount) public view returns (bool) {
        return coin.canMintNewCoins(_amount);
    }
    
    function getTokenPrice() public view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(coin.liquidityPair());
        (uint256 res0, uint256 res1,) = pair.getReserves();
        if(res0 == 0 && res1 == 0) {
            return 0;
        }
        uint256 mainRes = address(pair.token0()) == address(coin) ? res0 : res1;
        uint256 secondaryRes = mainRes == res0 ? res1: res0;
        uint256 decimals = coin.decimals();
        return (mainRes * (10 ** decimals)) / secondaryRes;
        
    }
    
    function getAveragePrice() public view returns (uint256) {
        uint256 averagePrice = 0;
        uint256 amount = 0;
        for (uint256 i = 0; i <= hourlyIndex; i++) {
            if(hourlyPrices[i] > 0) {
                averagePrice += hourlyPrices[i];
                amount++;
            }
        }
        return averagePrice.div(amount);
    }  
    
    function getPriceDifference(int256 newPrice, int256 oldPrice) public view returns (uint256) {
        int256 percentageDifference = (newPrice - oldPrice) * 100  * 10000 / oldPrice; //mul 10000 for floating accuracy
        if(percentageDifference < 0) {
            percentageDifference *= -1;
        }
        uint256 absPercentageDifference = uint256(percentageDifference);
        if(absPercentageDifference > maxEmissionIncrease) {
            absPercentageDifference = maxEmissionIncrease;
        }
        return absPercentageDifference; 
    }
    
    function getNewEmissionRate(uint256 percentage, bool isPositiveChange) public view returns (uint256) {
        uint256 newEmissionRate = coinPerBlock;
        if(isPositiveChange) {
            newEmissionRate = newEmissionRate.add(newEmissionRate.mul(percentage).div(1000000));
        } else {
            newEmissionRate = newEmissionRate.sub(newEmissionRate.mul(percentage).div(1000000));
        }
        return newEmissionRate;
    }
    
    function getLpSupply(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfos[_pid];
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        return lpSupply;
    }
    
    function pendingCoin(uint256 _pid, address _user) external view returns (uint256)
    {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][_user];
        uint256 accCoinPerShare = pool.accCoinPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 coinReward = multiplier.mul(coinPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accCoinPerShare = accCoinPerShare.add(coinReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accCoinPerShare).div(1e12).sub(user.rewardDebt);
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFee, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFee <= 10000,"set: deposit fee can't exceed 10 %");
        if(_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfos.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accCoinPerShare: 0,
                depositFee: _depositFee
            })
        );
        emit NewPool(address(_lpToken), poolInfos.length - 1);
    }
    
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfos[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 coinReward = multiplier.mul(coinPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        if(canClaimRewards(coinReward + coinReward.div(10))) {
            coin.mint(devAddress, coinReward.div(10));
            coin.mint(address(this), coinReward);
        }
        pool.accCoinPerShare = pool.accCoinPerShare.add(coinReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }
    
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        if(user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCoinPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeCoinTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFee > 0) {
                uint256 depositFeeAmount = _amount.mul(pool.depositFee).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFeeAmount);
                user.amount = user.amount.add(_amount).sub(depositFeeAmount);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accCoinPerShare).div(1e12);
        if(pool.lpToken == coin) {
            depositedCoins += _amount;
        }
        emit Deposit(msg.sender, _pid, _amount);
        checkPriceUpdate();
    }
    
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: withdraw amount can't exceed users deposited amount");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCoinPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeCoinTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCoinPerShare).div(1e12);
        if(pool.lpToken == coin) {
            depositedCoins -= _amount;
        }
        emit Withdraw(msg.sender, _pid, _amount);
        checkPriceUpdate();
    }
    
    function claim(uint256 _pid) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCoinPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeCoinTransfer(msg.sender, pending);
            emit Claim(msg.sender, _pid, pending);
        }
        user.rewardDebt = user.amount.mul(pool.accCoinPerShare).div(1e12);
    }
    
    // Withdraw without caring about rewards.
    function withdrawWithoutRewards(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
    
    
    function safeCoinTransfer(address _to, uint256 _amount) internal {
        uint256 coinBalance = coin.balanceOf(address(this)).sub(depositedCoins);
        bool transferSuccess = false;
        if (_amount > coinBalance) {
            transferSuccess = coin.transfer(_to, coinBalance);
        } else {
            transferSuccess = coin.transfer(_to, _amount);
        }
        require(transferSuccess, "safeCoinTransfer: transfer failed");
    }
    
    function updateLastAveragePrice(uint256 updatedPrice) internal {
        if(lastAveragePrice == 0) {
            lastAveragePrice = updatedPrice;
            return;
        }
        uint256 percentageDifference = getPriceDifference(int256(updatedPrice), int256(lastAveragePrice));
        uint256 newEmissionRate = getNewEmissionRate(percentageDifference, updatedPrice > lastAveragePrice);
        lastEmissionIncrease = percentageDifference;
        lastAveragePrice = updatedPrice;
        updateEmissionRate(newEmissionRate);
    }
    
    function checkPriceUpdate() public {
        if (lastPriceUpdateBlock < block.timestamp - 1 hours) {
            hourlyPrices[hourlyIndex++] = getTokenPrice();
            lastPriceUpdateBlock = block.timestamp;
        }
        if (
            lastEmissionUpdateBlock < block.timestamp - 24 hours &&
            hourlyIndex > 2
        ) {
            uint256 averagePrice = getAveragePrice();
            lastEmissionUpdateBlock = block.timestamp;
            hourlyIndex = 0;
            updateLastAveragePrice(averagePrice);
        }
    }
}