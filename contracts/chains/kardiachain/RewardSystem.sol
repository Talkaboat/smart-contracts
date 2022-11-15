// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../../libraries/TransferHelper.sol";
import "../../libraries/TimeLock.sol";
import "./interfaces/IKaiDexRouter.sol";

contract RewardSystem is Ownable, TimeLock {
    using Address for address;
    using SafeMath for uint256;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(address => bool) public _rewards;
    mapping(address => uint256) public _claimTimes;
    uint256 public nativeSwapFee = 10; //10% fee
    
    address public _oracleWallet = 0x76049b7cAaB30b8bBBdcfF3A1059d9147dBF7B19;
    address public _devWallet = 0xc559aCc356D3037EC6dbc33a20587051188b8634;
    
    IERC20 public _rewardToken;
    uint256 public _maxAmountPerReceive = 10000000 ether;
    uint256 public _timeBetweenClaims = 1 days;
    address public _weth = 0xAF984E23EAA3E7967F3C5E007fbe397D8566D23d;

    IKaiDexRouter public _router = IKaiDexRouter(0xbAFcdabe65A03825a131298bE7670c0aEC77B37f);
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SentRewards(address indexed owner, uint256 indexed amount);
    event SentRewardsETH(address indexed owner, uint256 indexed amount, uint256 indexed fees);
    event EnabledRewards(address indexed owner);
    event ChangedFee(uint256 indexed previousFee, uint256 indexed fee);
    event ChangedRewardToken(address indexed previousToken, address indexed newToken);
    event ChangedOracleWallet(address indexed previousAddress, address indexed newAddress);
    event ChangedMaxAmountPerReceive(uint256 indexed previousAmount, uint256 indexed amount);
    event EmergencyWithdraw(address indexed owner);
    
    constructor(IERC20 rewardToken) {
        _rewardToken = rewardToken;
        changeOracleWallet(_oracleWallet);
    }
    
    receive() external payable {}
    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    function getBalance() public view returns (uint256) {
        return _rewardToken.balanceOf(address(this));
    }

    function getEthBalance() public view returns (uint256) {
        return address(this).balance;
    }



    function canClaim(address user) public view returns (bool) {
        return _claimTimes[user] + _timeBetweenClaims <= block.timestamp;
    }
    
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */

    function adjustMaxAmountPerReceive(uint256 newAmount) public onlyOwner locked("adjustMaxAmountPerReceive") {
        emit ChangedMaxAmountPerReceive(_maxAmountPerReceive, newAmount);
        _maxAmountPerReceive = newAmount;
    }
    
    function updateRewardToken(IERC20 rewardToken) public onlyOwner locked("updateRewardToken") {
        require(rewardToken != _rewardToken, "ABOAT:updateRewardToken: You can't update the exact same tokens");
        emit ChangedRewardToken(address(_rewardToken), address(rewardToken));
        _rewardToken = rewardToken;
    }
    
    function changeOracleWallet(address oracleWallet) public onlyOwner locked("changeOracleWallet") {
        transferOwnership(oracleWallet);
        address previous = _oracleWallet;
        _oracleWallet = oracleWallet;
        emit ChangedOracleWallet(previous, _oracleWallet);
    }
    
    function setRouter(IKaiDexRouter router) public onlyOwner {
        _router = router;
    }

    function changeFee(uint256 newFee) public onlyOwner locked("changeFee") {
        emit ChangedFee(nativeSwapFee, newFee);
        nativeSwapFee = newFee;
    }

    function emergencyWithdraw() public onlyOwner {
        TransferHelper.safeTransfer(address(_rewardToken), owner(), getBalance());
        uint256 ethBalance = address(this).balance;
        if(ethBalance > 0) {
            TransferHelper.safeTransferETH(address(owner()), ethBalance);
        }
        emit EmergencyWithdraw(owner());
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function sendRewards(uint256 amount, address user, uint256 fee) public onlyOwner {
        require(address(_router) != address(0), "ABOAT::sendReward: There is no router defined to swap tokens for eth");
        require(amount <= getBalance(), "ABOAT::sendReward: Can't send more rewards than in reward system!");
        require(amount <= _maxAmountPerReceive, "ABOAT::sendReward: Can't send more rewards than limit!");
        require(canClaim(user), "ABOAT::sendReward: Can't claim more than once per day");
        require(amount > fee, "ABOAT::sendReward");
        _claimTimes[user] = block.timestamp;
        amount = amount.sub(fee);
        uint256 userEth = address(this).balance;
        swapTokensForEth(fee);
        TransferHelper.safeTransferETH(address(owner()), address(this).balance.sub(userEth));
        TransferHelper.safeTransfer(address(_rewardToken), user, amount);
        emit SentRewards(user, amount);
    }
    
    function sendRewardAsEth(uint256 amount, address user) public onlyOwner {
        require(address(_router) != address(0), "ABOAT::sendRewardsAsEth: There is no router defined to swap tokens for eth");
        require(amount <= getBalance(), "ABOAT::sendRewardsAsEth: Can't send more rewards than in reward system!");
        require(amount <= _maxAmountPerReceive, "ABOAT::sendRewardsAsEth: Can't send more rewards than limit!");
        require(canClaim(user), "ABOAT::sendRewardsAsEth: Can't claim more than once per day");
        _claimTimes[user] = block.timestamp;
        uint256 ethBefore = address(this).balance;
        swapTokensForEth(amount);
        uint256 userEth = address(this).balance.sub(ethBefore);
        uint256 fee = userEth.div(nativeSwapFee);
        userEth = userEth.sub(fee);
        TransferHelper.safeTransferETH(address(owner()), fee);
        TransferHelper.safeTransferETH(user, userEth);
        emit SentRewardsETH(user, userEth, fee);
    }
    
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the Enodi pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(_rewardToken);
        path[1] = _weth;

        _rewardToken.approve(address(_router), tokenAmount);

        // make the swap
        _router.swapExactTokensForKAISupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }
}