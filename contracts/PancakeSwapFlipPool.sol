// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./AboatToken.sol";
import "./interfaces/IMasterChefContractor.sol";
import "./flip_interfaces/IPancakeSwapMasterChef.sol";
import "./libraries/TransferHelper.sol";
import "./MasterEntertainer.sol";

contract PancakeSwapFlipPool is Ownable, IMasterChefContractor {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;    
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    IPancakeSwapMasterChef masterChef;
    IERC20 public rewardToken;
    
    AboatToken public coin;
    address public rewardSystem;
    
    IUniswapV2Router02 router;
    
    MasterEntertainer masterEntertainer;
    
    uint256 constant MIN_AMOUNT_TO_SWAP = 1 ether;
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SetRewardSystem(address indexed user, address indexed newAddress);
    
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */
    
    
    
    constructor(AboatToken _coin, IUniswapV2Router02 _router, IERC20 _rewardToken, address _rewardSystem, IPancakeSwapMasterChef _masterChef, MasterEntertainer _masterEntertainer) {
        coin = _coin;
        router = _router;
        masterChef = _masterChef;
        masterEntertainer = _masterEntertainer;
        rewardToken = _rewardToken;
        rewardSystem = _rewardSystem;
        rewardToken.approve(address(masterEntertainer), type(uint256).max);
    }  

    /* =====================================================================================================================
                                                        Set Functions
    ===================================================================================================================== */
    function setRewardSystem(address _rewardSystem) public onlyOwner{
        rewardSystem = _rewardSystem;
        emit SetRewardSystem(msg.sender, rewardSystem);
    }
    
    function setRouter(IUniswapV2Router02 _router) public onlyOwner {
        router = _router;
    }
    
    /* =====================================================================================================================
                                                        Get Functions
    ===================================================================================================================== */
    function getMasterChef() external override view returns (address) {
        return address(masterChef);
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */
    function recieve() public payable { }
    
    function deposit(uint256 _pid, uint256 _amount) external override {
        _deposit(_pid, _amount);
    }
    
    function _deposit(uint256 _pid, uint256 _amount) internal {
        if(_pid == 0) {
            enterStake(_pid, _amount);
        } else {
            masterChef.deposit(_pid, _amount);
        }
        swapToken();
    }
    
    function withdraw(uint256 _pid, uint256 _amount, IERC20 _token, address _sender) external override {
        if(_pid == 0) {
            leaveStake(_pid, _amount, _token, _sender);
        } else {
            masterChef.withdraw(_pid, _amount);
        }
        _token.safeTransfer(_sender, _amount);
        swapToken();
    }
    
    
    function emergencyWithdraw(uint256 _pid, uint256 _amount, IERC20 _token, address _sender) external override {
        masterChef.withdrawWithoutRewards(_pid);
        _token.safeTransfer(_sender, _amount);
        _deposit(_pid, _token.balanceOf(address(this)));
        
    }
    
    function enterStake(uint256 _pid, uint256 _amount) internal {
        masterChef.deposit(_pid, _amount);
        swapToken();
    }
    
    function leaveStake(uint256 _pid, uint256 _amount, IERC20 _token, address _sender) internal {
        masterChef.withdraw(_pid, _amount);
        _token.safeTransfer(_sender, _amount);
        swapToken();
    }
    
    
    function swapToken() internal {
        uint256 balanceToSwap = rewardToken.balanceOf(address(this));
        if(balanceToSwap >= MIN_AMOUNT_TO_SWAP) {
            uint256 ethBalance = swapForEth(rewardToken, balanceToSwap);
            swapEthForTokens(ethBalance);
            safeCoinTransfer(rewardSystem, coin.balanceOf(address(this)));
        }
       
    }
    
    function swapForEth(IERC20 token, uint256 amount) internal returns (uint256) {
        uint256 initialBalance = address(this).balance;
                
        // swap tokens for ETH
        swapTokensForEth(token, amount);
        
        return address(this).balance.sub(initialBalance);
    }
    
    function swapTokensForEth(IERC20 token, uint256 tokenAmount) internal {
        // generate the Enodi pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();

        token.approve(address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            0
        );
    }
    
    function swapEthForTokens(uint256 tokenAmount) internal {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(coin);
        
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: tokenAmount}(
            0, // accept any amount of ETH
            path,
            address(this),
            0
        );
    }
    
    function safeCoinTransfer(address _to, uint256 _amount) internal {
        uint256 coinBalance = coin.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > coinBalance) {
            transferSuccess = coin.transfer(_to, coinBalance);
        } else {
            transferSuccess = coin.transfer(_to, _amount);
        }
        require(transferSuccess, "safeCoinTransfer: transfer failed");
    }
    
}