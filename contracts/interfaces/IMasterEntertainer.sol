pragma solidity ^0.8.7;

interface IMasterEntertainer {
    function updatePrice() external; 
    function getBalanceOf(address _user, uint256 _vesting) external view returns (uint256);
}