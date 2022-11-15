// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../../libraries/TransferHelper.sol";
import "../../libraries/Liquify.sol";
import "../../interfaces/IMasterEntertainer.sol";
import "../../interfaces/IAboatToken.sol";

contract AboatToken is ERC20, Liquify, IAboatToken {
    using SafeMath for uint256;
    using Address for address;
    uint256 public maxDistribution = 1000000000000 ether;
    constructor() ERC20("Aboat Token", "ABOAT") {

    }

    function liquidityPair() public override view returns (address) {
        return _liquidityPair;
    }
    
    function canMintNewCoins(uint256 _amount) public override view returns (bool) {
        return totalSupply() + _amount <= maxDistribution;
    }

    function mint(address _to, uint256 _amount) public override onlyOwner {
        _mint(_to, _amount);
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override nonReentrant {

    }
}