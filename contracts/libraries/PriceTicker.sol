// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../TalkaboatToken.sol";

abstract contract PriceTicker is Ownable {
    using SafeMath for uint256;
    using Address for address;   
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    TalkaboatToken public coin;
    address public lpAddress;
    
    uint256[] public hourlyPrices;
    uint256 public hourlyIndex = 0;
    
    uint256 public lastPriceUpdateBlock;
    uint256 public lastAveragePrice = 0;
    uint256 public previousAveragePrice = 0;
        
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event ChangedCoin(address indexed previousCoin, address indexed newCoin);

    constructor() {
        for(uint8 i = 0; i < 24; i++) {
            hourlyPrices.push(0);
        }
    }
    
        
    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    
    function setCoin(TalkaboatToken _coin) public onlyOwner {
        require(coin != _coin, "TAB::setCoin: Can't replace the same coin");
        address previousCoin = address(coin);
        coin = _coin;
        lpAddress = coin.liquidityPair();
        hourlyIndex = 0;
        emit ChangedCoin(previousCoin, address(coin));
    }
        
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    function getAveragePrice() public view returns (uint256) {
        uint256 averagePrice = 0;
        uint256 amount = 0;
        for (uint256 i = 0; i <= hourlyIndex; i++) {
            if(hourlyPrices[i] > 0) {
                averagePrice += hourlyPrices[i];
                amount++;
            }
        }
        return averagePrice.div(amount);
    }  
    
    function getPriceDifference(int256 newPrice, int256 oldPrice) public pure returns (uint256) {
        int256 percentageDifference = (newPrice - oldPrice) * 100  * 10000 / oldPrice; //mul 10000 for floating accuracy
        if(percentageDifference < 0) {
            percentageDifference *= -1;
        }
        uint256 absPercentageDifference = uint256(percentageDifference);
        return absPercentageDifference; 
    }

    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function getTokenPrice() public returns (uint256) {
        address coinLpAddress = coin.liquidityPair();
        if(coinLpAddress != lpAddress) {
            lpAddress = coinLpAddress;
            hourlyIndex = 0;
        }
        IUniswapV2Pair pair = IUniswapV2Pair(lpAddress);
        (uint256 res0, uint256 res1,) = pair.getReserves();
        if(res0 == 0 && res1 == 0) {
            return 0;
        }
        ERC20 tokenB = address(pair.token0()) == address(coin) ? ERC20(pair.token1()) : ERC20(pair.token1());
        uint256 mainRes = address(pair.token0()) == address(coin) ? res1 : res0;
        uint256 secondaryRes = mainRes == res0 ? res1: res0;
        return (mainRes * (10 ** tokenB.decimals())) / secondaryRes;
    }
    
    function updateLastAveragePrice(uint256 updatedPrice) internal {
        if(lastAveragePrice == 0) {
            previousAveragePrice = lastAveragePrice;
            lastAveragePrice = updatedPrice;
            return;
        }

    }
    
    function checkPriceUpdate() virtual public  {
        if (lastPriceUpdateBlock < block.timestamp - 1 hours) {
            uint256 tokenPrice = getTokenPrice();
            hourlyPrices[hourlyIndex++] = tokenPrice;
            lastPriceUpdateBlock = block.timestamp;
        }

    }
}