pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMasterChefContractor {
    function getMasterChef() external view returns (address);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount, IERC20 token, address sender) external;
    function emergencyWithdraw(uint256 _pid, uint256 _amount, IERC20 _token, address _sender) external;
}