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
    
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event Claimed(address indexed owner, uint256 indexed amount);
    
    
    constructor(IERC20 _token, uint256 _cycles, uint256 _releasePerCycle, uint256 _instantRelease, uint256 _releaseOnDayFromNow) {
        token = _token;
        releasePerCycle = _releasePerCycle;
        instantRelease = _instantRelease;
        for(uint index = 0; index <= _cycles; index++) {
            claimDays.push(1 days * _releaseOnDayFromNow + 30 days * index);
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
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function claim() public onlyOwner {
        require(nextClaim() >= block.timestamp, "ABOAT::claim: You can't claim before set date");
        uint256 balance = 0;
        uint256 release = releasePerCycle + instantRelease;
        instantRelease = 0;
        if(address(token) != address(0)) {
            balance = token.balanceOf(address(this));
            TransferHelper.safeTransfer(address(token), msg.sender, balance > release ? release : balance);
        } else {
            balance = address(this).balance;
            TransferHelper.safeTransferETH(msg.sender, balance > release ? release : balance);
        }
    }
}