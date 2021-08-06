// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

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

contract TalkaboatToken is ERC20, Ownable, Liquify {
    using SafeMath for uint256;
    using Address for address;
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    uint256 public maxDistribution = 1000000000000 ether;
    
    uint public totalFeesPaid;
    uint public devFeesPaid;
    uint public donationFeesPaid;
    uint public reDistributionFeesPaid;
    uint public liquidityFeesPaid;
    
    //Master Entertainer contract
    MasterEntertainer public _masterEntertainer;
    
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event MasteEntertainerTransferred(address indexed previousMasterEntertainer, address indexed newMasterEntertainer);
    event MaxDistributionChanged(uint256 indexed newMaxDistribution);
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */
    
    
    constructor() ERC20("Talkaboat Token", "TAB") {
         mint(msg.sender, 500000000000 ether);  
    }
    
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    function setMasterEntertainer(address _newMasterEntertainer) public onlyOwner {
        require(_newMasterEntertainer != address(_masterEntertainer) && _newMasterEntertainer != address(0), "TAB::setMasterEntertainer: Master entertainer can\'t equal previous master entertainer or zero address");
        address previousEntertainer = address(_masterEntertainer);
        _masterEntertainer = MasterEntertainer(_newMasterEntertainer);
        excludeFromAll(_newMasterEntertainer);
        transferOwnership(_newMasterEntertainer);
        emit MasteEntertainerTransferred(previousEntertainer, _newMasterEntertainer);
    }
    
    function setMaxDistribution(uint256 _newDistribution) public onlyMaintainerOrOwner {
        require(_newDistribution > totalSupply(), "setMaxDistribution: Distribution can't be lower than the current total supply");
        maxDistribution = _newDistribution;
        emit MaxDistributionChanged(_newDistribution);
    }

    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    
    function maintainer() public view returns (address) {
        return _maintainer;
    }
  
    /**
     * @dev Returns the address is excluded from max transfer or not.
     */
    function isExcludedFromSenderTax(address _account) public view returns (bool) {
        return _excludedFromFeesAsSender[_account];
    }
    
    /**
     * @dev Returns the address is excluded from max transfer or not.
     */
    function isExcludedFromRecieverTax(address _account) public view returns (bool) {
        return _excludedFromFeesAsReciever[_account];
    }
    
    /**
     * @dev Returns the estimated tax Fee
    */
    function getTaxFee(address _sender) public view returns (uint256) {
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
    
    /*
    * @dev returns value of stored token balance from liquidity pair tokens (not address(this))
    */
    function liquidityTokenBalance() public view returns (uint256) {
        return IERC20(getLiquidityTokenAddress()).balanceOf(address(this));
    }
    
    function canMintNewCoins(uint256 _amount) public view returns (bool) {
        return totalSupply() + _amount <= maxDistribution;
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */
    
    // To receive BNB from _router when swapping
    receive() external payable {}
    
    function claimExceedingLiquidityTokenBalance() public onlyMaintainerOrOwner {
        require(liquidityTokenBalance() > 0, "TAB::claimExceedingLiquidityTokenBalance: No exceeding balance");
        TransferHelper.safeTransferFrom(getLiquidityTokenAddress(), address(this), msg.sender, liquidityTokenBalance());
    }
    
     /// @notice Creates `_amount` token to `_to`. Must only be called by the owner.
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(canMintNewCoins(_amount), "mint: Can't mint more talkaboat token than maxDistribution allows");
        _mint(_to, _amount);
    }
    
    function burn(uint256 _amount) public onlyMaintainerOrOwner {
        require(_amount <= balanceOf(address(this)), "TAB::burn: amount exceeds balance");
        _burn(address(this), _amount);
    }
    
        /// @dev overrides transfer function to meet tokenomics of talkaboat
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        // swap and liquify
        if (_swapAndLiquifyEnabled == true
            && address(_router) != address(0)
            && _liquidityPair != address(0)
            && sender != _liquidityPair
            && sender != owner()
            && sender != _maintainer) {
                
            swapAndLiquify();
        }

        if (recipient == address(0) || maximumTransferTaxRate == 0 || _excludedFromFeesAsReciever[recipient] || _excludedFromFeesAsSender[sender]) {
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