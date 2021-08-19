// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.7 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/TransferHelper.sol";

contract RewardSystem is Ownable {
    using Address for address;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(address => bool) public _rewards;
    uint256 public _gasCost = 2100000000000000;
    
    address public _oracleWallet;
    
    IERC20 public _rewardToken;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SentRewards(address indexed owner, uint256 indexed amount);
    event EnabledRewards(address indexed owner);
    event ChangedGasCost(uint256 indexed previousCost, uint256 indexed cost);
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
    
    function adjustGasCost(uint256 gasCost) public onlyOwner {
        emit ChangedGasCost(_gasCost, gasCost);
        _gasCost = gasCost;
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
    function sendRewards(uint256[] memory amounts, address[] memory addresses) public onlyOwner {
        require(amounts.length == addresses.length, "Error::addReward: amounts and addresses must have the same amount of entries");
        
        for(uint index = 0; index < addresses.length; index++) {
            if(_rewards[addresses[index]] && getBalance() >= amounts[index]) {
                TransferHelper.safeTransfer(address(_rewardToken), addresses[index], amounts[index]);
                _rewards[addresses[index]] = false;
                emit SentRewards(addresses[index], amounts[index]);
            }
        }
    }
    
    function sendRewardAndAdjustGasCost(uint256[] memory amounts, address[] memory addresses, uint256 gasCost) public onlyOwner {
        adjustGasCost(gasCost);
        sendRewards(amounts, addresses);
    }
    
    function claim() public payable {
        require(!_rewards[msg.sender], "Error::claim: Already allowed to recieve tokens");
        require(msg.value >= _gasCost, "Error::claim: Amount of bnb to claim should carry the cost to add the claimable");
        TransferHelper.safeTransferETH(_oracleWallet, msg.value);
        _rewards[msg.sender] = true;
        emit EnabledRewards(msg.sender);
    }
}