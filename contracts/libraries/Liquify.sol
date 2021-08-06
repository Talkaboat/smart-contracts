// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TransferHelper.sol";

abstract contract Liquify is ERC20, ReentrancyGuard, Ownable {
    using Address for address;
    using SafeMath for uint256;
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    //Transfer Tax
    //Transfer tax rate in basis points. default 50 => 0.5%
    uint16 public minimumTransferTaxRate = 50;
    uint16 public maximumTransferTaxRate = 500;
    
    uint16 public reDistributionRate = 40;
    uint16 public devRate = 20;
    uint16 public donationRate = 10;
    
    uint256 public _minAmountToLiquify = 100000 ether;
    bool public _swapAndLiquifyEnabled = true;
    
    address public _devWallet = 0x2EA9CA0ca8043575f2189CFF9897B575b0c7e857;          //Wallet where the dev fees will go to
    address public _donationWallet = 0xDBdbb811bd567C1a2Ac50159b46583Caa494d055;     //Wallet where donation fees will go to
    address public _rewardWallet = 0x2EA9CA0ca8043575f2189CFF9897B575b0c7e857;     //Wallet where rewards will be distributed
    
    address public _liquidityPair;
    
    address public _maintainer;  
    
    IUniswapV2Router02 public _router;
    
    mapping(address => bool) public _excludedFromFeesAsSender;
    mapping(address => bool) public _excludedFromFeesAsReciever;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event MaintainerTransferred(address indexed previousMaintainer, address indexed newMaintainer);
    event MinimumTransferTaxRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event MaximumTransferTaxRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event ReDistributionRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event DevRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event DonationRateUpdated(address indexed caller, uint256 previousRate, uint256 newRate);
    event SwapAndLiquifyEnabledUpdated(address indexed caller, bool enabled);
    event MinAmountToLiquifyUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event RouterUpdated(address indexed caller, address indexed router, address indexed pair);
    event ChangedLiqudityPair(address indexed caller, address indexed pair);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
    
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */
    modifier taxFree {
        uint16 _minimumTransferTaxRate = minimumTransferTaxRate;
        uint16 _maximumTransferTaxRate = maximumTransferTaxRate;
        minimumTransferTaxRate = 0;
        maximumTransferTaxRate = 0;
        _;
        minimumTransferTaxRate = _minimumTransferTaxRate;
        maximumTransferTaxRate = _maximumTransferTaxRate;
    }
    
    modifier onlyMaintainerOrOwner() {
        require(owner() == msg.sender || _maintainer == msg.sender, "operator: caller is not allowed to call this function");
        _;
    }
    
    constructor() {
        setMaintainer(msg.sender);
        excludeFromAll(_devWallet);
        excludeFromAll(_donationWallet);
        updateRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
    }
    
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    function setMaintainer(address _newMaintainer) public onlyMaintainerOrOwner {
        require(_newMaintainer != _maintainer && _newMaintainer != address(0), "TAB::setMaintainer: Maintainer can\'t equal previous maintainer or zero address");
        address previousMaintainer = _maintainer;
        _maintainer = _newMaintainer;
        excludeFromAll(_newMaintainer);
        emit MaintainerTransferred(previousMaintainer, _maintainer);
    }
    
    function setLiquidityPair(address _tokenB) public onlyMaintainerOrOwner {
        _liquidityPair = IUniswapV2Factory(_router.factory()).getPair(address(this), _tokenB);
        if(_liquidityPair == address(0)) {
            _liquidityPair = IUniswapV2Factory(_router.factory()).createPair(address(this), _tokenB);
        }
        emit ChangedLiqudityPair(msg.sender, _liquidityPair);
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function excludeFromAll(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsSender[_excludee] = true;
        _excludedFromFeesAsReciever[_excludee] = true;
    }
    
    function excludeTransferFeeAsSender(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsSender[_excludee] = true;
    }
    
    function excludeFromFeesAsReciever(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsReciever[_excludee] = true;
    }
    
    function includeForAll(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsSender[_excludee] = false;
        _excludedFromFeesAsReciever[_excludee] = false;
    }
    
    function includeTransferFeeAsSender(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsSender[_excludee] = false;
    }
    
    function includeForFeesAsReciever(address _excludee) public onlyMaintainerOrOwner {
        _excludedFromFeesAsReciever[_excludee] = false;
    }
    
    function updateMinimumTransferTaxRate(uint16 _transferTaxRate) public onlyMaintainerOrOwner {
        require(_transferTaxRate <= maximumTransferTaxRate, "TAB::updateMinimumTransferTaxRate: minimumTransferTaxRate must not exceed maximumTransferTaxRate.");
        emit MinimumTransferTaxRateUpdated(msg.sender, minimumTransferTaxRate, _transferTaxRate);
        minimumTransferTaxRate = _transferTaxRate;
    }
    
    function updateMaxTransferAmountRate(uint16 _maxTransferAmountRate) public onlyMaintainerOrOwner {
        require(_maxTransferAmountRate <= 10000, "TAB::updateMaxTransferAmountRate: Max transfer amount rate must not exceed the maximum rate.");
        emit MaximumTransferTaxRateUpdated(msg.sender, maximumTransferTaxRate, _maxTransferAmountRate);
        maximumTransferTaxRate = _maxTransferAmountRate;
    }
    
    function updateMaximumTransferTaxRate(uint16 _transferTaxRate) public onlyMaintainerOrOwner {
        require(_transferTaxRate >= minimumTransferTaxRate, "TAB::updateMinimumTransferTaxRate: minimumTransferTaxRate must not exceed maximumTransferTaxRate.");
        emit MaximumTransferTaxRateUpdated(msg.sender, minimumTransferTaxRate, _transferTaxRate);
        maximumTransferTaxRate = _transferTaxRate;
    }
    
    function updateRedistributionRate(uint16 _rate) public onlyMaintainerOrOwner {
        require(_rate <= 100, "TAB::updateRedistributionRate: Redistribution rate must not exceed the maximum rate.");
        emit ReDistributionRateUpdated(msg.sender, reDistributionRate, _rate);
        reDistributionRate = _rate;
    }
    
    function updateDevRate(uint16 _rate) public onlyMaintainerOrOwner {
        require(_rate <= 100, "TAB::updateDevRate: Burn rate must not exceed the maximum rate.");
        emit DevRateUpdated(msg.sender, devRate, _rate);
        devRate = _rate;
    }
    
    function updateDonationRate(uint16 _rate) public onlyMaintainerOrOwner {
        require(_rate <= 100, "TAB::updateDonationRate: Burn rate must not exceed the maximum rate.");
        emit DonationRateUpdated(msg.sender, donationRate, _rate);
        donationRate = _rate;
    }
    
    function updateSwapAndLiquifyEnabled(bool _enabled) public onlyMaintainerOrOwner {
        emit SwapAndLiquifyEnabledUpdated(msg.sender, _enabled);
        _swapAndLiquifyEnabled = _enabled;
    }
    
    function updateRouter(address router) public onlyMaintainerOrOwner {
        _router = IUniswapV2Router02(router);
        setLiquidityPair(_router.WETH());
        excludeTransferFeeAsSender(router);
        emit RouterUpdated(msg.sender, router, _liquidityPair);
    }
    
    /* =====================================================================================================================
                                                    Liquidity Functions
    ===================================================================================================================== */
    
    /*
    * @dev Function to swap the stored liquidity fee tokens and add them to the current liquidity pool
    */
    function swapAndLiquify() public taxFree {
        uint256 contractTokenBalance = balanceOf(address(this));
        if (contractTokenBalance >= _minAmountToLiquify) {
            IUniswapV2Pair pair = IUniswapV2Pair(_liquidityPair);
            // only min amount to liquify
            uint256 liquifyAmount = _minAmountToLiquify;

            // split the liquify amount into halves
            uint256 half = liquifyAmount.div(2);
            uint256 otherHalf = liquifyAmount.sub(half);


            address tokenA = address(pair.token0());
            address tokenB = address(pair.token1());
            require(tokenA != tokenB, "Invalid liqudity pair: Pair can\'t contain the same token twice");
            
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
            0
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
            0
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
            0
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
            0
        );
    }
    
}