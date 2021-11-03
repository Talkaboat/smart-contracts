 // SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./AboatToken.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/PriceTicker.sol";
import "./interfaces/IMasterChefContractor.sol";

contract MasterEntertainer is Ownable, ReentrancyGuard, PriceTicker {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;    
    
    /* =====================================================================================================================
                                                        Structs
    ===================================================================================================================== */
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastDeposit;
    }
    
    struct PoolInfo {
        IMasterChefContractor contractor;
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accCoinPerShare;
        uint16 depositFee; 
        uint256 pid;
        uint256 lockPeriod;
    }
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;
    
    PoolInfo[] public poolInfos;
    
    address public devAddress;
    address public feeAddress;
    
    uint256 public coinPerBlock;
    uint256 public startBlock;
    uint256 public totalAllocPoint = 0;
    uint256 public depositedCoins = 0;
    uint256 public lastEmissionUpdateBlock;
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
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event SetMaxEmissionIncrease(address indexed user, uint16 newMaxEmissionIncrease);
    event UpdateEmissionRate(address indexed user, uint256 newEmission);
    event UpdatedPool(uint256 indexed pid);
    
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */

    
    constructor(AboatToken _coin, address _devaddr, address _feeAddress, uint256 _startBlock) {
        coin = _coin;
        devAddress = _devaddr;
        feeAddress = _feeAddress;
        coinPerBlock = 4000 ether;
        startBlock = _startBlock;
        //alloc point, lp token, pool id, deposit fee, contractor, lock period in days, update pool
        add(100, IERC20(coin), 0, 400, IMasterChefContractor(address(0)), 30, false);
        add(150, IERC20(coin), 0, 300, IMasterChefContractor(address(0)), 90, false);
        add(250, IERC20(coin), 0, 200, IMasterChefContractor(address(0)), 180, false);
        add(400, IERC20(coin), 0, 100, IMasterChefContractor(address(0)), 360, false);
    }  

    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    function setDevAddress(address _devAddress) public onlyOwner locked("setDevAddress") {
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }
    
    function massUpdatePools() public {
        uint256 length = poolInfos.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    
    function setPoolVariables(uint256 _pid, uint256 _allocPoint, uint16 _depositFee, uint256 _lockPeriod, bool _withUpdate) public onlyOwner {
        require(_depositFee <= 10000,"set: deposit fee can't exceed 10 %");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfos[_pid].allocPoint).add(_allocPoint);
        poolInfos[_pid].allocPoint = _allocPoint;
        poolInfos[_pid].depositFee = _depositFee;
        poolInfos[_pid].lockPeriod = _lockPeriod * 1 days;
        emit UpdatedPool(_pid);
    }
    
    function updateEmissionRate(uint256 _coinPerBlock) public onlyOwner locked("updateEmissionRate") {
        massUpdatePools();
        coinPerBlock = _coinPerBlock;
        emit UpdateEmissionRate(msg.sender, _coinPerBlock);
    }
    
    function updateEmissionRateInternal(uint256 _coinPerBlock) internal {
        massUpdatePools();
        coinPerBlock = _coinPerBlock;
        emit UpdateEmissionRate(address(this), _coinPerBlock);
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
        uint256 lpSupply = 0;
        if(address(pool.lpToken) == address(coin)) {
            lpSupply = depositedCoins;
        }
        else if(address(pool.contractor) == address(0)) {
            lpSupply = pool.lpToken.balanceOf(address(this));
        } else {
            lpSupply = pool.lpToken.balanceOf(address(pool.contractor.getMasterChef()));
        }
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
    function add(uint256 _allocPoint, IERC20 _lpToken, uint256 _pid, uint16 _depositFee, IMasterChefContractor _contractor, uint256 _lockPeriod,  bool _withUpdate) public onlyOwner {
        require(_depositFee <= 10000,"set: deposit fee can't exceed 10 %");
        if(_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfos.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accCoinPerShare: 0,
                depositFee: _depositFee,
                pid: _pid,
                contractor: _contractor,
                lockPeriod: _lockPeriod * 1 days
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
            user.lastDeposit = block.timestamp;
            uint256 realAmount = _amount;
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFee > 0) {
                uint256 depositFeeAmount = _amount.mul(pool.depositFee).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFeeAmount);
                realAmount = _amount.sub(depositFeeAmount);
                user.amount = user.amount.add(realAmount);
            } else {
                user.amount = user.amount.add(_amount);
            }
            if(address(pool.contractor) != address(0)) {
                pool.lpToken.approve(address(pool.contractor), realAmount);
                pool.contractor.deposit(pool.pid, realAmount);
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
            require(user.lastDeposit.add(pool.lockPeriod) <= block.timestamp, "ABOAT::withdraw: Can't withdraw before locking period ended.");
            user.amount = user.amount.sub(_amount);
            if(address(pool.contractor) != address(0)) {
                pool.contractor.withdraw(pool.pid, _amount, address(msg.sender));
            } else {
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accCoinPerShare).div(1e12);
        if(pool.lpToken == coin) {
            depositedCoins -= _amount;
        }
        emit Withdraw(msg.sender, _pid, _amount);
        checkPriceUpdate();
    }
    
    function claim(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCoinPerShare).div(1e12).sub(user.rewardDebt);
        
        if (pending > 0) {
            safeCoinTransfer(msg.sender, pending);
            emit Claim(msg.sender, _pid, pending);
        }
        if(address(pool.contractor) != address(0)) {
            pool.contractor.withdraw(pool.pid, 0, address(msg.sender));
        }
        user.rewardDebt = user.amount.mul(pool.accCoinPerShare).div(1e12);
        checkPriceUpdate();
    }
    
    // Withdraw without caring about rewards.
    function withdrawWithoutRewards(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.lastDeposit.add(pool.lockPeriod) <= block.timestamp, "ABOAT::withdrawWithoutRewards: Can't withdraw before locking period ended.");
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
         if(address(pool.contractor) != address(0)) {
             pool.contractor.emergencyWithdraw(pool.pid, amount, address(msg.sender));
         } else {
            pool.lpToken.safeTransfer(address(msg.sender), amount);
         }
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
    
    function checkPriceUpdate() override public {
        if(address(coin) == address(0) || address(coin.liquidityPair()) == address(0)) {
            return;
        }
        if (lastPriceUpdateBlock < block.timestamp - 1 hours) {
            uint256 tokenPrice = getTokenPrice();
            hourlyPrices[hourlyIndex++] = tokenPrice;
            lastPriceUpdateBlock = block.timestamp;
        }
        if (lastEmissionUpdateBlock < block.timestamp - 24 hours && hourlyIndex > 2) {
            uint256 averagePrice = getAveragePrice();
            lastEmissionUpdateBlock = block.timestamp;
            hourlyIndex = 0;
            bool shouldUpdateEmissionRate = lastAveragePrice != 0;
            updateLastAveragePrice(averagePrice);
            if(shouldUpdateEmissionRate) {
                updateEmissionRateByPriceDifference();
            }
        }
    }
    
    function updateEmissionRateByPriceDifference() internal {
        uint256 percentageDifference = getPriceDifference(int256(lastAveragePrice), int256(previousAveragePrice));
        if(percentageDifference > maxEmissionIncrease) {
            percentageDifference = maxEmissionIncrease;
        }
        uint256 newEmissionRate = getNewEmissionRate(percentageDifference, lastAveragePrice > previousAveragePrice);
        lastEmissionIncrease = percentageDifference;
        lastAveragePrice = lastAveragePrice;
        updateEmissionRateInternal(newEmissionRate);
    }
}