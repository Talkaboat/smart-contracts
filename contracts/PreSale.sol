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
    IERC20 public rewardToken; //Aboat Token
    IERC20 public paymentToken; //BNB
    uint256 public pricePerToken;   //How much BNB per Aboat Token
    uint256 public limit;   //how much can each investors spend at maximum
    uint256 public softcap; //minimum required sell (how many tokens should be sold)
    uint256 public soldTokens; //how many token are currently sold
    uint256 public saleEnded = 0; //block when the sale ended (0 = still ongoing)
    uint256 public afterDays; //after how many days can investors make their initial claim
    uint256 public period = 1; //How many days are between each claim 
    uint256 public initialClaimPercentage = 400; //How much can investors claim directly after sale ended (default: 40%)
    uint256 public percentagePerPeriod = 50; //How much can investors claim per period after the initial claim (default: 5% -> 1 year vesting)
    
    
    bool public requireWhitelist = true;    //flag to determine whether buyers have to be whitelisted or not
    
    mapping(address => bool) public whitelisted;
    mapping(address => uint256) public bought;  //tracks who bought how many aboat token
    mapping(address => uint256) public claimed; //tracks who claimed how much percentage of his tokens
    mapping(address => uint256) public claimedTokens; //tracks who claimed how many aboat token
    mapping(address => address) public lastClaimAddress; //In case we have to swap the token contract

    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SaleEnded(uint256 indexed claimDate);
    event Claimed(address indexed owner, uint256 indexed amount);
    event Bought(address indexed buyer, uint256 indexed amount);
    event ChangeRewardToken(address indexed newToken);
    
    constructor(IERC20 _rewardToken, IERC20 _paymentToken, uint256 _limit, uint256 _softcap, uint256 _price) {
        require(_price > 0, "ABOAT::error: Price has to be higher than zero");
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
        emit SaleEnded(saleEnded.add(afterDays.mul(1 days)));
    }
    
    function disableWhitelist() public onlyOwner {
        require(requireWhitelist, "ABOAT:disableWhitelist: Whitelist is already disabled");
        requireWhitelist = false;
    }
    
    //Will only be required if the security audit displays errors that have to be fixed
    //which would mean a new contract has to be deployed.
    //With this function we can ensure that early investors will still be able to get the right coin before release
    function updateRewardToken(IERC20 _newRewardToken) public onlyOwner {
        require(_newRewardToken != rewardToken, "ABOAT::updateRewardToken: New reward should be different from current.");
        require(_newRewardToken.balanceOf(address(this)) == rewardToken.balanceOf(address(this)), "ABOAT::updateRewardToken: The contract should contain atleast the same amount of tokens as from the current rewardToken");
        rewardToken = _newRewardToken;
        emit ChangeRewardToken(address(rewardToken));
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
    
    function getCurrentPercentage() public view returns (uint256) {
        uint256 percentage = saleEnded > 0 && block.timestamp > saleEnded.add(afterDays * 1 days) ? block.timestamp.sub(saleEnded.add(afterDays * 1 days)).div(period * 1 days).mul(50).add(400) : 0;
        return percentage > 1000 ? 1000 : percentage;
    }
    
    
    /* =====================================================================================================================
                                                        Investors
    ===================================================================================================================== */
    
    function buy(uint256 amount) public payable {
        require(saleEnded == 0, "ABOAT::buy: Sale already ended!");
        require(amount >= 1 ether / 20, "ABOAT::buy: minimum buy is 0.05 BNB");
        require(whitelisted[msg.sender] || !requireWhitelist, "ABOAT::buy: You're not whitelisted for this sale!");
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
        lastClaimAddress[msg.sender] = address(paymentToken);
        emit Bought(msg.sender, amount);
    }
    
    //returns the reward token if softcap is reached and owner ended the sale
    //otherwise it returns the paid paymentToken
    function claim() public {
        require(saleEnded != 0, "ABOAT::claim: Sale is not over yet!");
        require(block.timestamp >= saleEnded.add((afterDays.mul(1 days))), "ABOAT::claim: Claim is not available yet.");
        uint256 currentPercentage = getCurrentPercentage();
        require(currentPercentage > 0, "ABOAT::claim: The percentage of token you can claim is currently zero. Please try again later");
        if(lastClaimAddress[msg.sender] != address(rewardToken)) {
            lastClaimAddress[msg.sender] = address(rewardToken);
            claimed[msg.sender] = 0;
            claimedTokens[msg.sender] = 0;
        }
        require(claimed[msg.sender] < currentPercentage, "ABOAT::claim: Already claimed your currently eligible tokens");
        if(softcap <= soldTokens) {
            claimed[msg.sender] = currentPercentage;
            uint256 amount = bought[msg.sender].mul(currentPercentage).div(1000).mul(1e18).div(pricePerToken);
            claimedTokens[msg.sender] = amount;
            if(address(rewardToken) != address(0)) {
                TransferHelper.safeTransfer(address(rewardToken), msg.sender, amount);
            } else {
                TransferHelper.safeTransferETH(msg.sender, amount);
            }
            emit Claimed(msg.sender, amount);
        } else {
            claimed[msg.sender] = 1000; //
            if(address(paymentToken) != address(0)) {
                TransferHelper.safeTransfer(address(paymentToken), msg.sender, bought[msg.sender]);
            } else {
                TransferHelper.safeTransferETH(msg.sender, bought[msg.sender]);
            }
            emit Claimed(msg.sender, bought[msg.sender]);
        }

    }
}