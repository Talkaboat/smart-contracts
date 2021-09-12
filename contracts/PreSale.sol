// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./libraries/TransferHelper.sol";

contract PreSale is Ownable {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    IERC20 public rewardToken;
    IERC20 public paymentToken;
    uint256 public pricePerToken;
    uint256 public limit;
    uint256 public softcap; //minimum required sell (how many tokens should be sold)
    uint256 public soldTokens;
    uint256 public saleEnded = 0;
    uint256 public afterDays;
    
    mapping(address => bool) public whitelisted;
    mapping(address => uint256) public bought;
    mapping(address => bool) public claimed;

    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SaleEnded(uint256 indexed claimDate);
    event Claimed(address indexed owner, uint256 indexed amount);
    event Bought(address indexed buyer, uint256 indexed amount);
    constructor(IERC20 _rewardToken, IERC20 _paymentToken, uint256 _limit, uint256 _softcap, uint256 _price) {
        rewardToken = _rewardToken;
        paymentToken = _paymentToken;
        limit = _limit;
        softcap = _softcap;   //softcap in terms of sold tokens
        pricePerToken = _price;
    }
    
    
    /* =====================================================================================================================
                                                        Owner
    ===================================================================================================================== */
    
    function claimAndEndSale(uint256 _afterDays) public onlyOwner {
        require(saleEnded == 0, "ABOAT::claimAndEndSale: Sale already ended");
        saleEnded = block.timestamp;
        if(softcap <= soldTokens) {
            //Community can claim their entry after a certain period (should be between public sale and official release (liquidity))
            afterDays = _afterDays;
            if(address(paymentToken) != address(0)) {
                TransferHelper.safeTransfer(address(paymentToken), msg.sender, paymentToken.balanceOf(address(this)));
            } else {
                TransferHelper.safeTransferETH(msg.sender, address(this).balance);
            } 
        } else {
            //Community can claim their entry directly as the sale failed.
            afterDays = 0;
             if(address(rewardToken) != address(0)) {
                TransferHelper.safeTransfer(address(rewardToken), msg.sender, rewardToken.balanceOf(address(this)));
            } else {
                TransferHelper.safeTransferETH(msg.sender,  address(this).balance);
            }
        }
        emit SaleEnded(saleEnded.add(afterDays.mul(1 minutes)));
    }
    
    //Will only be required if the security audit displays errors that have to be fixed
    //which would mean a new contract has to be deployed.
    //Early investors should still be able to get the right coin
    function updateRewardToken(IERC20 _newRewardToken) public onlyOwner {
        require(_newRewardToken != rewardToken, "ABOAT::updateRewardToken: New reward should be different from current.");
        require(_newRewardToken.balanceOf(address(this)) == rewardToken.balanceOf(address(this)), "ABOAT::updateRewardToken: The contract should contain atleast the same amount of tokens as from the current rewardToken");
        rewardToken = _newRewardToken;
    }
    
    
    function whitelist(address[] memory addresses) public onlyOwner {
        for(uint index = 0; index < addresses.length; index++) {
            whitelisted[addresses[index]] = true;
        }
    }
    
    /* =====================================================================================================================
                                                        General
    ===================================================================================================================== */
    
    function getRemainingBalance() public view returns (uint256) {
        if(address(rewardToken) == address(0)) {
            return address(this).balance.sub(soldTokens);
        } else {
            return rewardToken.balanceOf(address(this)).sub(soldTokens);
        }
    }
    
    
    /* =====================================================================================================================
                                                        Investors
    ===================================================================================================================== */
    
    function buy(uint256 amount) public payable {
        require(saleEnded == 0, "ABOAT::buy: Sale already ended!");
        require(whitelisted[msg.sender], "ABOAT::buy: You're not whitelisted for this sale!");
        bool isEthToken = address(paymentToken) == address(0);
        require(!isEthToken || msg.value == amount, "ABOAT::buy: Sent value doesn't meet the given amount");
        require(bought[msg.sender].add(amount) <= limit, "ABOAT::buy: Amount would exceed the maximum allowed limit");
        uint256 amountBought = amount.mul(1e18).div(pricePerToken);
        require(getRemainingBalance().sub(amountBought) > 0, "ABOAT::buy: Amount would exceed the remaining balance");
        if(!isEthToken) {
            paymentToken.safeTransferFrom(address(msg.sender), address(this), amount);
        }
        bought[msg.sender] = bought[msg.sender].add(amount);
        soldTokens = soldTokens.add(amountBought);
        emit Bought(msg.sender, amount);
    }
    
    //returns the reward token if softcap is reached and owner ended the sale
    //otherwise it returns the paid paymentToken
    function claim() public {
        require(saleEnded != 0, "ABOAT::claim: Sale is not over yet!");
        require(!claimed[msg.sender], "ABOAT::claim: Already claimed tokens");
        require(block.timestamp >= saleEnded.add((afterDays.mul(1 minutes))), "ABOAT::claim: Claim is not available yet.");
        claimed[msg.sender] = true;
        uint256 amount = bought[msg.sender].mul(1e18).div(pricePerToken);
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