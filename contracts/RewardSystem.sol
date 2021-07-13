// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Address.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "./libraries/TransferHelper.sol";

contract RewardSystem is Ownable {
    using Address for address;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(address => uint256) public _rewards;
    uint256 public _gasCostPerMil = 46000000000000000;
    
    address public _oracleWallet;
    
    address public _rewardToken;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event AddedRewards(uint256 indexed entries);
    event ClaimedRewards(address indexed owner, uint256 indexed amount);
    
    constructor(address rewardToken) {
        _oracleWallet = msg.sender;
        _rewardToken = rewardToken;
    }
    
    receive() external payable {}
    
    
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    
    function adjustGasCostPerMil(uint256 gasCost) public onlyOwner {
        _gasCostPerMil = gasCost;
    }
    
    function updateRewardToken(address rewardToken) public onlyOwner {
        _rewardToken = rewardToken;
    }
    
    function changeOracleWallet(address oracleWallet) public onlyOwner {
        transferOwnership(oracleWallet);
        _oracleWallet = oracleWallet;
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function addReward(uint256[] memory amounts, address[] memory addresses) public onlyOwner {
        require(amounts.length == addresses.length, "Error::addReward: amounts and addresses must have the same amount of entries");
        for(uint index = 0; index < addresses.length; index++) {
            _rewards[addresses[index]] += amounts[index];
        }
        emit AddedRewards(addresses.length);
    }
    
    function claim(uint256 amount) public payable {
        require(_rewards[msg.sender] > 0, "Error::claim: Can't claim rewards if you don't have any");
        require(_rewards[msg.sender] >= amount, "Error::claim: Can't claim more rewards than you earned");
        require(msg.value >= _gasCostPerMil / 1000, "Error::claim: Amount of bnb to claim should carry the cost to add the claimable");
        TransferHelper.safeTransferETH(_oracleWallet, msg.value);
        TransferHelper.safeTransfer(_rewardToken, msg.sender, amount);
        emit ClaimedRewards(msg.sender, amount);
    }
}