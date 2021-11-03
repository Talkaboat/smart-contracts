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
import "./interfaces/IMasterChefContractor.sol";
import "./flip_interfaces/IPancakeSwapMasterChef.sol";
import "./libraries/TransferHelper.sol";

contract PancakeSwapFlipPool is Ownable, IMasterChefContractor {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;    
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    IPancakeSwapMasterChef masterChef;
    IERC20 public rewardToken;  //What do we get as reward?
    IERC20 public stakeToken;   //What do we stake to get reward?
    IERC20 public flipToken;    //What do we swap to?
    address public rewardSystem;
    
    IUniswapV2Router02 router;
    
    address masterEntertainer;
    
    uint256 constant MIN_AMOUNT_TO_SWAP = 1 ether;
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SetRewardSystem(address indexed user, address indexed newAddress);
    
    /* =====================================================================================================================
                                                        Modifier
    ===================================================================================================================== */
    
    
    
    constructor(IERC20 _flipToken, IERC20 _rewardToken, address _rewardSystem, IPancakeSwapMasterChef _masterChef, address _masterEntertainer) {
        flipToken = _flipToken;
        masterChef = _masterChef;
        masterEntertainer = _masterEntertainer;
        rewardToken = _rewardToken;
        rewardSystem = _rewardSystem;
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
    
    function getLiquidity(uint256 _pid) external override view returns (uint256) {
        (uint256 amount, ) = masterChef.userInfo(_pid, address(this));
        return amount;
    }
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */
    function recieve() public payable { }
    
    function deposit(uint256 _pid, uint256 _amount) external override {
        _deposit(_pid, _amount);
    }
    
    function _deposit(uint256 _pid, uint256 _amount) internal {
        stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        stakeToken.approve(address(masterChef), _amount);
        if(_pid == 0) {
            enterStake(_pid, _amount);
        } else {
            masterChef.deposit(_pid, _amount);
        }
        swapToken();
    }
    
    function withdraw(uint256 _pid, uint256 _amount, address _sender) external override {
        if(_pid == 0) {
            leaveStake(_pid, _amount, _sender);
        } else {
            masterChef.withdraw(_pid, _amount);
        }
        stakeToken.safeTransfer(_sender, _amount);
        swapToken();
    }
    
    
    function emergencyWithdraw(uint256 _pid, uint256 _amount, address _sender) external override {
        masterChef.withdrawWithoutRewards(_pid);
        stakeToken.safeTransfer(_sender, _amount);
        _deposit(_pid, stakeToken.balanceOf(address(this)));
        
    }
    
    function enterStake(uint256 _pid, uint256 _amount) internal {
        masterChef.deposit(_pid, _amount);
        swapToken();
    }
    
    function leaveStake(uint256 _pid, uint256 _amount, address _sender) internal {
        masterChef.withdraw(_pid, _amount);
        stakeToken.safeTransfer(_sender, _amount);
        swapToken();
    }
    
    
    function swapToken() internal {
        uint256 balanceToSwap = rewardToken.balanceOf(address(this));
        if(address(router) == address(0)) {
            safeflipTokenTransfer(masterEntertainer, balanceToSwap);
        }
        else if(balanceToSwap >= MIN_AMOUNT_TO_SWAP) {
            uint256 ethBalance = swapForEth(rewardToken, balanceToSwap);
            swapEthForTokens(ethBalance);
            safeflipTokenTransfer(rewardSystem, flipToken.balanceOf(address(this)));
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
        path[1] = address(flipToken);
        
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: tokenAmount}(
            0, // accept any amount of ETH
            path,
            address(this),
            0
        );
    }
    
    function safeflipTokenTransfer(address _to, uint256 _amount) internal {
        uint256 flipTokenBalance = flipToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > flipTokenBalance) {
            transferSuccess = flipToken.transfer(_to, flipTokenBalance);
        } else {
            transferSuccess = flipToken.transfer(_to, _amount);
        }
        require(transferSuccess, "safeflipTokenTransfer: transfer failed");
    }
    
}