// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./libraries/TransferHelper.sol";

contract Faucet {
    using Address for address;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    IERC20 public usdt;
    IERC20 public talkaboat;
    uint256 constant AMOUNT_USDT = 2000 ether;
    uint256 constant AMOUNT_TALKABOAT = 200000000 ether;
    uint16 constant MAX_REQUESTS = 5;
    mapping(address => uint16) public recieved;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SentCoins(address indexed owner);
    
    constructor(IERC20 _usdt, IERC20 _talkaboat) {
        usdt = _usdt;
        talkaboat = _talkaboat;
    }
    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    function remainingRequests() public view returns (uint16) {
        return MAX_REQUESTS - recieved[msg.sender];
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function request() public  {
        require(recieved[msg.sender] < 5, "TAB::request: You can't claim faucet more than 5 times.");
        require(usdt.balanceOf(address(this)) >= AMOUNT_USDT, "TAB::request: Not enough usdt left for faucet");
        require(talkaboat.balanceOf(address(this)) >= AMOUNT_TALKABOAT, "TAB::request: Not enough usdt left for faucet");
        recieved[msg.sender] += 1;
        TransferHelper.safeTransfer(address(usdt), msg.sender, AMOUNT_USDT);
        TransferHelper.safeTransfer(address(talkaboat), msg.sender, AMOUNT_TALKABOAT);
        emit SentCoins(msg.sender);
    }
    
}