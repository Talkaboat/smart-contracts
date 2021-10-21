// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/TimeLock.sol";

contract RewardSystem is Ownable, TimeLock {
    using Address for address;
    using SafeMath for uint256;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(address => bool) public _rewards;
    uint256 public _gasCost = 2100000000000000;
    
    address public _oracleWallet = 0x76049b7cAaB30b8bBBdcfF3A1059d9147dBF7B19;
    address public _devWallet = 0x2EA9CA0ca8043575f2189CFF9897B575b0c7e857;
    
    IERC20 public _rewardToken;
    
    IUniswapV2Router02 public _router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SentRewards(address indexed owner, uint256 indexed amount);
    event SentRewardsETH(address indexed owner, uint256 indexed amount, uint256 indexed fees);
    event EnabledRewards(address indexed owner);
    event ChangedGasCost(uint256 indexed previousCost, uint256 indexed cost);
    event ChangedRewardToken(address indexed previousToken, address indexed newToken);
    event ChangedOracleWallet(address indexed previousAddress, address indexed newAddress);
    
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
    
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    
    function adjustGasCost(uint256 gasCost) public onlyOwner locked("adjustGasCost") {
        emit ChangedGasCost(_gasCost, gasCost);
        _gasCost = gasCost;
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
    
    function setRouter(IUniswapV2Router02 router) public onlyOwner {
        _router = router;
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function sendRewards(uint256[] memory amounts, address[] memory addresses) public onlyOwner {
        require(amounts.length == addresses.length, "ABOAT::addReward: amounts and addresses must have the same amount of entries");
        
        for(uint index = 0; index < addresses.length; index++) {
            if(_rewards[addresses[index]] && getBalance() >= amounts[index]) {
                TransferHelper.safeTransfer(address(_rewardToken), addresses[index], amounts[index]);
                _rewards[addresses[index]] = false;
                emit SentRewards(addresses[index], amounts[index]);
            }
        }
    }
    
    function sendRewardsAsEth(uint256 amount, address user) public onlyOwner {
        require(address(_router) != address(0), "ABOAT::sendRewardsAsEth: There is no router defined to swap tokens for eth");
        uint256 ethBalance = address(this).balance;
        swapTokensForEth(amount);
        uint256 userEth = ethBalance.sub(address(this).balance).sub(_gasCost);
        TransferHelper.safeTransferETH(_oracleWallet, _gasCost);
        uint256 fee = userEth.mul(10).div(100);
        userEth = userEth.sub(fee);
        TransferHelper.safeTransferETH(_devWallet, fee);
        TransferHelper.safeTransferETH(user, userEth);
        emit SentRewardsETH(user, userEth, fee);
    }
    
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the Enodi pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        _rewardToken.approve(address(_router), tokenAmount);

        // make the swap
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(_rewardToken),
            block.timestamp
        );
    }
    
    function sendRewardAndAdjustGasCost(uint256[] memory amounts, address[] memory addresses, uint256 gasCost) public onlyOwner {
        adjustGasCost(gasCost);
        sendRewards(amounts, addresses);
    }
    
    function claim() public payable {
        require(!_rewards[msg.sender], "ABOAT::claim: Already allowed to recieve tokens");
        require(msg.value >= _gasCost, "ABOAT::claim: Amount of bnb to claim should carry the cost to add the claimable");
        TransferHelper.safeTransferETH(_oracleWallet, msg.value);
        _rewards[msg.sender] = true;
        emit EnabledRewards(msg.sender);
    }
}