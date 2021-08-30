// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./libraries/TransferHelper.sol";

contract PreSale is Ownable {
    using Address for address;
    using SafeMath for uint256;
        
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    IERC20 public rewardToken;
    IERC20 public paymentToken;
    uint256 public pricePerToken;
    uint256 public limit;
    uint256 public softcap; //minimum required sell (how many tokens should be sold)
    uint256 public soldTokens;
    bool public saleEnded;
    
    mapping(address => uint256) public bought;
    mapping(address => bool) public claimed;

    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event Claimed(address indexed owner, uint256 indexed amount);
    event Bought(address indexed buyer, uint256 indexed amount);
    constructor(IERC20 _rewardToken, IERC20 _paymentToken, uint256 _limit) {
        rewardToken = _rewardToken;
        paymentToken = _paymentToken;
        limit = _limit;
    }
    
    function claimAndEndSale() public onlyOwner {
        require(!saleEnded, "ABOAT::claimAndEndSale: Sale already ended");
        saleEnded = true;
        if(address(paymentToken) != address(0)) {
            TransferHelper.safeTransfer(address(paymentToken), msg.sender, paymentToken.balanceOf(address(this)));
        } else {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        }
    }
    
    function getRemainingBalance() public view returns (uint256) {
        if(address(rewardToken) == address(0)) {
            return address(this).balance - soldTokens;
        } else {
            return rewardToken.balanceOf(address(this)) - soldTokens;
        }
    }
    
    function buy(uint256 amount) public payable {
        require(!saleEnded, "ABOAT::buy: Sale already ended!");
        bool isEthToken = address(rewardToken) == address(0);
        require(!isEthToken || msg.value == amount, "ABOAT::buy: Sent value doesn't meet the given amount");
        require(bought[msg.sender] + amount <= limit, "ABOAT::buy: Amount would exceed the maximum allowed limit");
        bought[msg.sender] += amount;
        uint256 amountBought = amount / pricePerToken;
        soldTokens += amountBought;
        emit Bought(msg.sender, amount);
    }
    
    //returns the reward token if softcap is reached and owner ended the sale
    //otherwise it returns the paid paymentToken
    function claim() public {
        require(saleEnded, "ABOAT::claim: Sale is not over yet!");
        require(!claimed[msg.sender], "ABOAT::claim: Already claimed tokens");
        claimed[msg.sender] = true;
        uint256 amount = bought[msg.sender] / pricePerToken;
        if(softcap <= soldTokens) {
            if(address(rewardToken) != address(0)) {
                TransferHelper.safeTransfer(address(rewardToken), msg.sender, amount);
            } else {
                TransferHelper.safeTransferETH(msg.sender, amount);
            }
        } else {
            if(address(paymentToken) != address(0)) {
                TransferHelper.safeTransfer(address(paymentToken), msg.sender, bought[msg.sender]);
            } else {
                TransferHelper.safeTransferETH(msg.sender, bought[msg.sender]);
            }
        }
        emit Claimed(msg.sender, amount);
    }
}