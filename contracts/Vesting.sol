// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./libraries/TransferHelper.sol";

contract Vesting is Ownable {
    using Address for address;
    using SafeMath for uint256;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    IERC20 public token;
    uint256 public releasePerCycle;
    uint256 public instantRelease;
    uint256[] public claimDays;
    uint256 public claimed;
    uint256 public cycles;
    
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event Claimed(address indexed owner, uint256 indexed amount);
    
    
    constructor(IERC20 _token, uint256 _cycles, uint256 _releasePerCycle, uint256 _instantRelease, uint256 _releaseOnDayFromNow) {
        token = _token;
        releasePerCycle = _releasePerCycle;
        instantRelease = _instantRelease;
        cycles = _cycles;
        for(uint index = 0; index <= _cycles; index++) {
            claimDays.push((1 days * _releaseOnDayFromNow) + (30 days * index));
        }
    }
    
    receive() external payable {}
    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    function remainingBalance() public view returns (uint256) {
        if(address(token) != address(0)) {
            return token.balanceOf(address(this));
        } else {
            return address(this).balance;
        }
    }
    
    function nextClaim() public view returns (uint256) {
        require(claimed < claimDays.length, "ABOAT::nextClaim: You claimed all Token");
        return(claimDays[claimed]);
    }
    
    function getRemainingBalance() public view returns (uint256)  {
         if(address(token) != address(0)) {
             return token.balanceOf(address(this));
         } else {
             return address(this).balance;
         }
    }
    
    function balanceAfterCycles(uint256 _estimatedBalance) public view returns (uint256) {
        return (_estimatedBalance == 0 ? getRemainingBalance() : _estimatedBalance) - instantRelease - (releasePerCycle * (cycles + 1));
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function claim() public onlyOwner {
        require(nextClaim() >= block.timestamp, "ABOAT::claim: You can't claim before set date");
        uint256 balance = getRemainingBalance();
        require(balance > 0, "ABOAT::claim: There are no tokens left to be claimed!");
        uint256 release = releasePerCycle + instantRelease;
        release = balance > release ? release : balance;
        instantRelease = 0;
        if(address(token) != address(0)) {
            TransferHelper.safeTransfer(address(token), msg.sender, release);
        } else {
            TransferHelper.safeTransferETH(msg.sender, release);
        }
        emit Claimed(msg.sender, release);
    }
}