// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "./libraries/TransferHelper.sol";

contract RewardSystem is Ownable {
    using Address for address;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(address => uint256) public _rewards;
    uint256 public _gasCostPerMil = 51000000000000000;
    
    address public _oracleWallet;
    
    IERC20 public _rewardToken;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event AddedRewards(uint256 indexed entries);
    event ClaimedRewards(address indexed owner, uint256 indexed amount);
    event ChangedGasCostPerMil(uint256 indexed previousCost, uint256 indexed cost);
    event ChangedRewardToken(address indexed previousToken, address indexed newToken);
    
    
    constructor(IERC20 rewardToken) {
        _oracleWallet = msg.sender;
        _rewardToken = rewardToken;
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
    
    function adjustGasCostPerMil(uint256 gasCost) public onlyOwner {
        emit ChangedGasCostPerMil(_gasCostPerMil, gasCost);
        _gasCostPerMil = gasCost;
    }
    
    function updateRewardToken(IERC20 rewardToken) public onlyOwner {
        require(rewardToken != _rewardToken, "Error:updateRewardToken: You can't update the exact same tokens");
        emit ChangedRewardToken(address(_rewardToken), address(rewardToken));
        _rewardToken = rewardToken;
    }
    
    function changeOracleWallet(address oracleWallet) public onlyOwner {
        transferOwnership(oracleWallet);
        _oracleWallet = oracleWallet;
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function addRewards(uint256[] memory amounts, address[] memory addresses) public onlyOwner {
        require(amounts.length == addresses.length, "Error::addReward: amounts and addresses must have the same amount of entries");
        for(uint index = 0; index < addresses.length; index++) {
            _rewards[addresses[index]] += amounts[index];
        }
        emit AddedRewards(addresses.length);
    }
    
    function addRewardAndAdjustGasCost(uint256[] memory amounts, address[] memory addresses, uint256 gasCost) public onlyOwner {
        adjustGasCostPerMil(gasCost);
        addRewards(amounts, addresses);
    }
    
    function claim(uint256 amount) public payable {
        require(_rewards[msg.sender] > 0, "Error::claim: Can't claim rewards if you don't have any");
        require(_rewards[msg.sender] >= amount, "Error::claim: Can't claim more rewards than you earned");
        require(msg.value >= _gasCostPerMil / 1000, "Error::claim: Amount of bnb to claim should carry the cost to add the claimable");
        TransferHelper.safeTransferETH(_oracleWallet, msg.value);
        TransferHelper.safeTransfer(address(_rewardToken), msg.sender, amount);
        emit ClaimedRewards(msg.sender, amount);
    }
}