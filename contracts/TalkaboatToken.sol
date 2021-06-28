// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./libraries/TransferHelper.sol";
import "./MasterEntertainer.sol";

contract TalkaboatToken is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    uint256 public maxDistribution = 1000000000000 ether;
    //Transfer Tax
    //Transfer tax rate in basis points. default 50 => 0.5%
    uint16 public minimumTransferTaxRate = 50;
    uint16 public maximumTransferTaxRate = 500;
    uint16 public constant MAXIMUM_TAX_RATE = 1000; 
    
    uint16 public reDistributionRate = 20; //% that will be put back into rewards
    uint16 public devRate = 20;
    uint16 public donationRate = 20;
    
    //Paid fee statistic
    uint public totalFeesPaid;
    uint public devFeesPaid;
    uint public donationFeesPaid;
    uint public reDistributionFeesPaid;
    uint public liquidityFeesPaid;
    
    //Anti-Whale transfer 
    uint16 private maxTransferAmountRate = 10000;    //default: total supply can be send
    
    //Liquidity settings
    //Minimum amount before liquify. default: 100000 TAB
    uint256 private _minAmountToLiquify = 100000 ether;
    bool private _swapAndLiquifyEnabled = true;
    bool private _inSwapAndLiquify = false;
    
    //Maintainer
    address private _maintainer;                                                    //The one who will manage fee structure, liquidity pair etc.
    
    //Master Entertainer contract
    MasterEntertainer private _masterEntertainer;
    //Router contract
    IUniswapV2Router02 private _router;
    
    address private _devWallet = 0x2EA9CA0ca8043575f2189CFF9897B575b0c7e857;          //Wallet where the dev fees will go to
    address private _donationWallet = 0xDBdbb811bd567C1a2Ac50159b46583Caa494d055;     //Wallet where donation fees will go to
    
    address private _liquidityPair;
    
    mapping(address => bool) private _excludedFromMaxTransfer;
    mapping(address => bool) private _excludedFromFeesAsSender;
    mapping(address => bool) private _excludedFromFeesAsReciever;
    
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event MaintainerTransferred(address indexed previousMaintainer, address indexed newMaintainer);
    event MasteEntertainerTransferred(address indexed previousMasterEntertainer, address indexed newMasterEntertainer);
    //Events that could be triggered by owner and maintainer
    event MinimumTransferTaxRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event MaximumTransferTaxRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event ReDistributionRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event DevRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event DonationRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event MaxTransferAmountRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event SwapAndLiquifyEnabledUpdated(address indexed caller, bool enabled);
    event MinAmountToLiquifyUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event RouterUpdated(address indexed caller, address indexed router, address indexed pair);
    event ChangedLiqudityPair(address indexed caller, address indexed pair);
    event MaxDistributionChanged(uint256 indexed newMaxDistribution);
    //Events that can be triggered by contract (from everyone)
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
    
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */
    modifier onlyMaintainerOrOwner() {
        require(owner() == msg.sender || _maintainer == msg.sender, "operator: caller is not allowed to call this function");
        _;
    }
    
    modifier lockLiquify {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }
    
    /*
    * @dev modifier which excludes tax on transfer for the given transaction
    */
    modifier taxFree {
        uint16 _minimumTransferTaxRate = minimumTransferTaxRate;
        uint16 _maximumTransferTaxRate = maximumTransferTaxRate;
        minimumTransferTaxRate = 0;
        maximumTransferTaxRate = 0;
        _;
        minimumTransferTaxRate = minimumTransferTaxRate;
        maximumTransferTaxRate = _maximumTransferTaxRate;
    }
    
    /*
    * @dev anti whale modifier to check if transfer amount exceeds maximum transfer amount
    */
    modifier antiWhale(address sender, address recipient, uint256 amount) {
        if (maxTransferAmount() > 0) {
            if (
                _excludedFromMaxTransfer[sender] == false
                && _excludedFromMaxTransfer[recipient] == false
            ) {
                require(amount <= maxTransferAmount(), "Anti Whale: Transfer amount exceeds the maxTransferAmount");
            }
        }
        _;
    }
    
    constructor() ERC20("Talkaboat Token", "TAB") {
         setMaintainer(msg.sender);
         excludeFromAll(_devWallet);
         excludeFromAll(_donationWallet);
         mint(msg.sender, 500000000000 ether);  
         updateRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
    }
    
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    
    function setMasterEntertainer(address _newMasterEntertainer) public onlyMaintainerOrOwner {
        require(_newMasterEntertainer != address(_masterEntertainer) && _newMasterEntertainer != address(0), 'TAB::setMasterEntertainer: Master entertainer can\'t equal previous master entertainer or zero address');
        address previousEntertainer = address(_masterEntertainer);
        _masterEntertainer = MasterEntertainer(_newMasterEntertainer);
        excludeFromAll(_newMasterEntertainer);
        emit MasteEntertainerTransferred(previousEntertainer, _newMasterEntertainer);
    }
    
    function setMaintainer(address _newMaintainer) public onlyMaintainerOrOwner {
        require(_newMaintainer != _maintainer && _newMaintainer != address(0), 'TAB::setMaintainer: Maintainer can\'t equal previous maintainer or zero address');
        address previousMaintainer = _maintainer;
        _maintainer = _newMaintainer;
        excludeFromAll(_newMaintainer);
        emit MaintainerTransferred(previousMaintainer, _maintainer);
    }
    
    function setMaxDistribution(uint256 _newDistribution) public onlyMaintainerOrOwner {
        require(_newDistribution > totalSupply(), "setMaxDistribution: Distribution can't be lower than the current total supply");
        maxDistribution = _newDistribution;
        emit MaxDistributionChanged(_newDistribution);
    }
    
    function excludeFromAll(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromMaxTransfer[_excludee] = true;
        _excludedFromFeesAsSender[_excludee] = true;
        _excludedFromFeesAsReciever[_excludee] = true;
    }
    
    function excludeFromMaxTransfer(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromMaxTransfer[_excludee] = true;
    }
    
    function excludeTransferFeeAsSender(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsSender[_excludee] = true;
    }
    
    function excludeFromFeesAsReciever(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsReciever[_excludee] = true;
    }
    
    function includeForAll(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromMaxTransfer[_excludee] = false;
        _excludedFromFeesAsSender[_excludee] = false;
        _excludedFromFeesAsReciever[_excludee] = false;
    }
    
    function includeForMaxTransfer(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromMaxTransfer[_excludee] = false;
    }
    
    function includeTransferFeeAsSender(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsSender[_excludee] = false;
    }
    
    function includeForFeesAsReciever(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsReciever[_excludee] = false;
    }
    
    /**
     * @dev Update the transfer tax rate.
     * Can only be called by the current maintainer or owner.
     */
    function updateMinimumTransferTaxRate(uint16 _transferTaxRate) public onlyMaintainerOrOwner {
        require(_transferTaxRate <= MAXIMUM_TAX_RATE, "TAB::updateMinimumTransferTaxRate: Transfer tax rate must not exceed the set maximum rate.");
        require(_transferTaxRate <= maximumTransferTaxRate, "TAB::updateMinimumTransferTaxRate: minimumTransferTaxRate must not exceed maximumTransferTaxRate.");
        emit MinimumTransferTaxRateUpdated(msg.sender, minimumTransferTaxRate, _transferTaxRate);
        minimumTransferTaxRate = _transferTaxRate;
    }
    
    /**
     * @dev Update the transfer tax rate.
     * Can only be called by the current maintainer or owner.
     */
    function updateMaximumTransferTaxRate(uint16 _transferTaxRate) public onlyMaintainerOrOwner {
        require(_transferTaxRate <= MAXIMUM_TAX_RATE, "TAB::updateMinimumTransferTaxRate: Transfer tax rate must not exceed the set maximum rate.");
        require(_transferTaxRate >= minimumTransferTaxRate, "TAB::updateMinimumTransferTaxRate: minimumTransferTaxRate must not exceed maximumTransferTaxRate.");
        emit MaximumTransferTaxRateUpdated(msg.sender, minimumTransferTaxRate, _transferTaxRate);
        maximumTransferTaxRate = _transferTaxRate;
    }

    /**
     * @dev Update the burn rate.
     * Can only be called by the current maintainer or owner.
     */
    function updateBurnRate(uint16 _rate) public onlyMaintainerOrOwner {
        require(_rate <= 100, "END::updateBurnRate: Burn rate must not exceed the maximum rate.");
        emit ReDistributionRateUpdated(msg.sender, reDistributionRate, _rate);
        reDistributionRate = _rate;
    }
    
    /**
     * @dev Update the burn rate.
     * Can only be called by the current maintainer or owner.
     */
    function updateDevRate(uint16 _rate) public onlyMaintainerOrOwner {
        require(_rate <= 100, "END::updateBurnRate: Burn rate must not exceed the maximum rate.");
        emit DevRateUpdated(msg.sender, devRate, _rate);
        devRate = _rate;
    }
    
    /**
     * @dev Update the burn rate.
     * Can only be called by the current maintainer or owner.
     */
    function updateDonationRate(uint16 _rate) public onlyMaintainerOrOwner {
        require(_rate <= 100, "END::updateBurnRate: Burn rate must not exceed the maximum rate.");
        emit DonationRateUpdated(msg.sender, donationRate, _rate);
        donationRate = _rate;
    }

    /**
     * @dev Update the max transfer amount rate.
     * Can only be called by the current maintainer or owner.
     */
    function updateMaxTransferAmountRate(uint16 _maxTransferAmountRate) public onlyMaintainerOrOwner {
        require(_maxTransferAmountRate <= 10000, "END::updateMaxTransferAmountRate: Max transfer amount rate must not exceed the maximum rate.");
        emit MaxTransferAmountRateUpdated(msg.sender, maxTransferAmountRate, _maxTransferAmountRate);
        maxTransferAmountRate = _maxTransferAmountRate;
    }
    
    /**
     * @dev Update the swapAndLiquifyEnabled.
     * Can only be called by the current operator.
     */
    function updateSwapAndLiquifyEnabled(bool _enabled) public onlyMaintainerOrOwner {
        emit SwapAndLiquifyEnabledUpdated(msg.sender, _enabled);
        _swapAndLiquifyEnabled = _enabled;
    }

    /**
     * @dev Update the swap router.
     * Can only be called by the current operator.
     */
    function updateRouter(address router) public onlyMaintainerOrOwner {
        _router = IUniswapV2Router02(router);
        setLiquidityPair(_router.WETH());
        excludeTransferFeeAsSender(router);
        emit RouterUpdated(msg.sender, router, _liquidityPair);
    }
    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    
    function maintainer() public view returns (address) {
        return _maintainer;
    }
    
    /**
     * @dev Returns the max transfer amount.
    */
    function maxTransferAmount() public view returns (uint256) {
        return totalSupply().mul(maxTransferAmountRate).div(10000);
    }
    
    /**
     * @dev Returns the address is excluded from max transfer or not.
     */
    function isExcludedFromMaxTransfer(address _account) public view returns (bool) {
        return _excludedFromMaxTransfer[_account];
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
        require(liquidityTokenBalance() > 0, 'TAB::claimExceedingLiquidityTokenBalance: No exceeding balance');
        TransferHelper.safeTransferFrom(getLiquidityTokenAddress(), address(this), msg.sender, liquidityTokenBalance());
    }
    
     /// @notice Creates `_amount` token to `_to`. Must only be called by the owner.
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(canMintNewCoins(_amount), "mint: Can't mint more talkaboat token than maxDistribution allows");
        _mint(_to, _amount);
    }
    
    function burn(uint256 _amount) public onlyMaintainerOrOwner {
        require(_amount <= balanceOf(address(this)), 'TAB::burn: amount exceeds balance');
        _burn(address(this), _amount);
    }

    /**
     * @dev Add new liqudity pair to _liquidityPairs.
     */
    function setLiquidityPair(address _tokenB) public onlyMaintainerOrOwner {
        _liquidityPair = IUniswapV2Factory(_router.factory()).getPair(address(this), _tokenB);
        if(_liquidityPair == address(0)) {
            _liquidityPair = IUniswapV2Factory(_router.factory()).createPair(address(this), _tokenB);
        }
        emit ChangedLiqudityPair(msg.sender, _liquidityPair);
    }
    
        /// @dev overrides transfer function to meet tokenomics of talkaboat
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override antiWhale(sender, recipient, amount) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        // swap and liquify
        if (
            _swapAndLiquifyEnabled == true
            && _inSwapAndLiquify == false
            && address(_router) != address(0)
            && _liquidityPair != address(0)
            && sender != _liquidityPair
            && sender != owner()
            && sender != _maintainer
        ) {
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
            super._transfer(sender, address(_masterEntertainer), reDistributionAmount);
            super._transfer(sender, address(this), liquidityAmount);
            super._transfer(sender, recipient, sendAmount);
            super._transfer(sender, _devWallet, devAmount);
            super._transfer(sender, _donationWallet, donationAmount);
            amount = sendAmount;
            totalFeesPaid += taxAmount;
            devFeesPaid += devAmount;
            donationFeesPaid += donationAmount;
            liquidityFeesPaid += liquidityAmount;
        }
        checkPriceUpdate();
    }

    function checkPriceUpdate() public nonReentrant {
        if(address(_masterEntertainer) != address(0)) {
            _masterEntertainer.checkPriceUpdate();
        }
    }
    
    /* =====================================================================================================================
                                                    Liquidity Functions
    ===================================================================================================================== */
    
    /*
    * @dev Function to swap the stored liquidity fee tokens and add them to the current liquidity pool
    */
    function swapAndLiquify() public lockLiquify taxFree {
        uint256 contractTokenBalance = balanceOf(address(this));
        uint256 maxTransfer = maxTransferAmount();
        contractTokenBalance = contractTokenBalance > maxTransfer ? maxTransfer : contractTokenBalance;
        if (contractTokenBalance >= _minAmountToLiquify) {
            IUniswapV2Pair pair = IUniswapV2Pair(_liquidityPair);
            // only min amount to liquify
            uint256 liquifyAmount = _minAmountToLiquify;

            // split the liquify amount into halves
            uint256 half = liquifyAmount.div(2);
            uint256 otherHalf = liquifyAmount.sub(half);


            address tokenA = address(pair.token0());
            address tokenB = address(pair.token1());
            require(tokenA != tokenB, 'Invalid liqudity pair: Pair can\'t contain the same token twice');
            
            bool isWeth = tokenA == _router.WETH() || tokenB == _router.WETH();
            uint256 newBalance = 0;
            if(isWeth) {
               swapAndLiquifyEth(half, otherHalf);
            } else {
                swapAndLiquifyTokens(tokenA != address(this) ? tokenA : tokenB, half, otherHalf);
            }

            emit SwapAndLiquify(half, newBalance, otherHalf);
        }
    }
    
    function swapForEth(uint256 amount) private returns (uint256) {
        uint256 initialBalance = address(this).balance;
                
        // swap tokens for ETH
        swapTokensForEth(amount);
        
        return address(this).balance.sub(initialBalance);
    }
    
    function swapAndLiquifyEth(uint256 half, uint256 otherHalf) private {
        uint256 newBalance = swapForEth(half);
        addLiquidityETH(otherHalf, newBalance);
    }
    
    function swapAndLiquifyTokens(address tokenB, uint256 half, uint256 otherHalf) private {
        IERC20 tokenBContract = IERC20(tokenB);
        uint256 ethAmount = swapForEth(half);
        uint256 initialBalance = tokenBContract.balanceOf(address(this));
        swapEthForTokens(ethAmount, tokenB);
        uint256 newBalance = tokenBContract.balanceOf(address(this)).sub(initialBalance);
        addLiquidity(otherHalf, newBalance, tokenB);
    }
    
    function swapEthForTokens(uint256 tokenAmount, address tokenB) private {
        address[] memory path = new address[](2);
        path[0] = _router.WETH();
        path[1] = tokenB;
        
        _router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: tokenAmount}(
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev Swap tokens for eth
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the Enodi pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        _approve(address(this), address(_router), tokenAmount);

        // make the swap
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }
    
    function addLiquidity(uint256 tokenAmount, uint256 otherAmount, address tokenB) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(_router), tokenAmount);
        IERC20(tokenB).approve(address(_router), otherAmount);
        _router.addLiquidity(
            address(this),
            tokenB,
            tokenAmount,
            otherAmount,
            0,
            0,
            address(0),
            block.timestamp
        );
    }

    /// @dev Add liquidity
    function addLiquidityETH(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(_router), tokenAmount);

        // add the liquidity
        _router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0), //burn lp token
            block.timestamp
        );
    }
}