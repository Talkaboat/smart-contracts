// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Liquify.sol";
import "./MasterEntertainer.sol";

contract AboatToken is ERC20, Liquify {
    using SafeMath for uint256;
    using Address for address;
    
    /* =====================================================================================================================
                                                        Anti-Bot Helper
    ===================================================================================================================== */
    struct Transactions {
        uint256 lastTransaction;
        uint16 recurrentTransactions;
    }
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    uint256 public maxDistribution = 1000000000000 ether;
    
    uint256 private releaseDate;
    uint16 public maxTxQuantity = 100;
    uint16 public maxRecurrentTransactions = 5;
    uint256 public gasCost = 2100000000000000;
    
    uint public totalFeesPaid;
    uint public devFeesPaid;
    uint public donationFeesPaid;
    uint public reDistributionFeesPaid;
    uint public liquidityFeesPaid;
    
    //Master Entertainer contract
    MasterEntertainer public _masterEntertainer;
    
    mapping(address => Transactions) private recurrentTransactions;
    mapping(address => bool) private blacklisted;
    mapping(address => bool) private requestedWhitelist;
    mapping(address => bool) private excludedFromBlacklistSender;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event MasteEntertainerTransferred(address indexed previousMasterEntertainer, address indexed newMasterEntertainer);
    event MaxDistributionChanged(uint256 indexed newMaxDistribution);
    event RequestedWhitelist(address indexed requestee);
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */
    
    
    constructor() ERC20("Aboat Token", "ABOAT") {
        releaseDate = block.number;
        // Token distribution: https://documentation.talkaboat.online/tokenomics/talkaboat-basics.html
        mint(msg.sender, 500000000000 ether);
        excludeFromAll(msg.sender);
    }
    
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    function setMasterEntertainer(address _newMasterEntertainer) public onlyMaintainerOrOwner locked("masterEntertainer") {
        require(_newMasterEntertainer != address(_masterEntertainer) && _newMasterEntertainer != address(0), "TAB::setMasterEntertainer: Master entertainer can\'t equal previous master entertainer or zero address");
        address previousEntertainer = address(_masterEntertainer);
        _masterEntertainer = MasterEntertainer(_newMasterEntertainer);
        excludeFromAll(_newMasterEntertainer);
        transferOwnership(_newMasterEntertainer);
        emit MasteEntertainerTransferred(previousEntertainer, _newMasterEntertainer);
    }
    
    function setMaxDistribution(uint256 _newDistribution) public onlyMaintainerOrOwner locked("max_distribution") {
        require(_newDistribution > totalSupply(), "TAB::setMaxDistribution: Distribution can't be lower than the current total supply");
        maxDistribution = _newDistribution;
        emit MaxDistributionChanged(_newDistribution);
    }
    
    function setMaxRecurrentTransactions(uint16 amount) public onlyMaintainerOrOwner {
        maxRecurrentTransactions = amount;
    }
    
    function setMaxTransactionQuantity(uint16 quantity) public onlyMaintainerOrOwner {
        maxTxQuantity = quantity;
    }
    
    function setGasCost(uint256 cost) public onlyMaintainerOrOwner {
        gasCost = cost;
    }

    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    function isExcludedFromSenderTax(address _account) public view returns (bool) {
        return _excludedFromFeesAsSender[_account];
    }
    
    function isExcludedFromRecieverTax(address _account) public view returns (bool) {
        return _excludedFromFeesAsReciever[_account];
    }
    
    function hasRequestedWhitelist(address user) public onlyMaintainerOrOwner view returns (bool) {
        return requestedWhitelist[user];
    }
    
    function getTaxFee(address _sender) public view returns (uint256) {
        //Anti-Bot: The first Blocks will have a 99% fee
        if(block.number < releaseDate + 100) {
            return 9000;
        }
        uint balance = balanceOf(_sender);
        if(balance > totalSupply()) {
            return maximumTransferTaxRate;
        }
        else if(balance < totalSupply() / 100000) {
            return minimumTransferTaxRate;
        }
        uint tax = balance * 100000 / totalSupply();
        if(tax >= maximumTransferTaxRate) {
            return maximumTransferTaxRate;
        } else if(tax <= minimumTransferTaxRate) {
            return minimumTransferTaxRate;
        }
        return tax;
    }
    
    function liquidityPair() public view returns (address) {
        return _liquidityPair;
    }
    
    function getLiquidityTokenAddress() public view returns (address) {
        IUniswapV2Pair pair = IUniswapV2Pair(_liquidityPair);
        address tokenA = address(pair.token0());
        address tokenB = address(pair.token1());
        return tokenA != address(this) ? tokenA : tokenB;
    }
    
    function liquidityTokenBalance() public view returns (uint256) {
        return IERC20(getLiquidityTokenAddress()).balanceOf(address(this));
    }
    
    function canMintNewCoins(uint256 _amount) public view returns (bool) {
        return totalSupply() + _amount <= maxDistribution;
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */
    
    receive() external payable {}
    
    function setupLiquidity() public onlyMaintainerOrOwner {
        require(releaseDate == 0, "TAB::setupLiquidity:Liquidity is already setup!");
        releaseDate = block.number;
    }
    
    function excludeFromBlacklistSender(address sender) public onlyMaintainerOrOwner {
        require(!excludedFromBlacklistSender[sender], "TAB::excludeFromBlacklistSender: sender is already excluded");
        excludedFromBlacklistSender[sender] = true;
    }
    
    function includeFromBlacklistSender(address sender) public onlyMaintainerOrOwner {
        require(excludedFromBlacklistSender[sender], "TAB::excludeFromBlacklistSender: sender is already included");
        excludedFromBlacklistSender[sender] = false;
    }
    
    function addTransaction(address sender) internal view returns (uint16) {
        Transactions memory userTransactions = recurrentTransactions[sender];
        if(userTransactions.lastTransaction + 5 minutes >= block.timestamp) {
            userTransactions.recurrentTransactions += 1;
        }
        userTransactions.lastTransaction = block.timestamp;
        return userTransactions.recurrentTransactions;
    }
    
    function getTransactions(address user) public onlyMaintainerOrOwner view returns (Transactions memory ) {
        return recurrentTransactions[user];
    }
    
    function blacklist(address user) public onlyMaintainerOrOwner {
        blacklisted[user] = true;
    }
    
    function whitelist(address user) public onlyMaintainerOrOwner {
        blacklisted[user] = true;
        requestedWhitelist[user] = false;
    }
    
    function requestWhitelist() public payable {
        require(blacklisted[msg.sender], "TAB::requestWhitelist: You are not blacklisted!");
        require(!requestedWhitelist[msg.sender], "TAB::requestWhitelist: You already requested whitelist!");
        require(msg.value >= gasCost, "TAB::requestWhitelist: Amount of bnb to claim should carry the cost to add the claimable");
        TransferHelper.safeTransferETH(_devWallet, msg.value);
        requestedWhitelist[msg.sender] = true;
        emit RequestedWhitelist(msg.sender);
    }
    
    function claimExceedingLiquidityTokenBalance() public onlyMaintainerOrOwner {
        require(liquidityTokenBalance() > 0, "TAB::claimExceedingLiquidityTokenBalance: No exceeding balance");
        TransferHelper.safeTransferFrom(getLiquidityTokenAddress(), address(this), msg.sender, liquidityTokenBalance());
    }
    
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(canMintNewCoins(_amount), "TAB::mint: Can't mint more talkaboat token than maxDistribution allows");
        _mint(_to, _amount);
    }
    
    function burn(uint256 _amount) public onlyMaintainerOrOwner {
        require(_amount <= balanceOf(address(this)), "TAB::burn: amount exceeds balance");
        _burn(address(this), _amount);
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        require(sender != address(0), "TAB::_transfer: transfer from the zero address");
        require(recipient != address(0), "TAB::_transfer: transfer to the zero address");
        require(amount > 0, "TAB::_transfer:Transfer amount must be greater than zero");
        require(amount <= balanceOf(sender), "TAB::_transfer:Transfer amount must be lower or equal senders balance");
        //Anti-Bot: If someone sends too many recurrent transactions in a short amount of time he will be blacklisted
        require(!blacklisted[sender], "TAB::_transfer:You're currently blacklisted. Please report to service@talkaboat.online if you want to get removed from blacklist!");
        //Anti-Bot: Disable transactions with more than 1% of total supply
        require(amount * 10000 / totalSupply() <= maxTxQuantity || sender == owner() || sender == maintainer(), "Your transfer exceeds the maximum possible amount per transaction");
        //Anti-Bot: If someone sends too many recurrent transactions in a short amount of time he will be blacklisted
        if(sender != owner() && sender != maintainer() && !excludedFromBlacklistSender[sender] && !excludedFromBlacklistSender[recipient] && addTransaction(sender) > maxRecurrentTransactions) {
            blacklisted[sender] = true;
            return;
        }
        
        if (address(_router) != address(0)
            && _liquidityPair != address(0)
            && sender != _liquidityPair
            && !_excludedFromFeesAsSender[sender]
            && sender != owner()
            && sender != maintainer()) {
            swapAndLiquify();
        }
        if ((block.number > releaseDate + 100 || sender == maintainer() || sender == owner()) && (recipient == address(0) || maximumTransferTaxRate == 0 || _excludedFromFeesAsReciever[recipient] || _excludedFromFeesAsSender[sender])) {
            super._transfer(sender, recipient, amount);
        } else {
            // default tax is 0.5% of every transfer
            uint256 taxAmount = amount.mul(getTaxFee(sender)).div(10000);
            uint256 reDistributionAmount = taxAmount.mul(reDistributionRate).div(100);
            uint256 devAmount = taxAmount.mul(devRate).div(100);
            uint256 donationAmount = taxAmount.mul(donationRate).div(100);
            uint256 liquidityAmount = taxAmount.sub(reDistributionAmount.add(devAmount).add(donationAmount));
            require(taxAmount == reDistributionAmount + liquidityAmount + devAmount + donationAmount, "TAB::transfer: Fee amount does not equal the split fee amount");
            uint256 sendAmount = amount.sub(taxAmount);
            require(amount == sendAmount + taxAmount, "TAB::transfer: amount to send with tax amount exceeds maximum possible amount");
            super._transfer(sender, address(this), liquidityAmount);
            super._transfer(sender, recipient, sendAmount);
            super._transfer(sender, _devWallet, devAmount);
            super._transfer(sender, _donationWallet, donationAmount);
            super._transfer(sender, _rewardWallet, reDistributionAmount);
            amount = sendAmount;
            totalFeesPaid += taxAmount;
            devFeesPaid += devAmount;
            donationFeesPaid += donationAmount;
            liquidityFeesPaid += liquidityAmount;
        }
        checkPriceUpdate();
    }

    function checkPriceUpdate() public {
        if(address(_masterEntertainer) != address(0)) {
            _masterEntertainer.checkPriceUpdate();
        }
    }
}