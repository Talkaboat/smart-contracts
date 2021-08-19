// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.7 <0.9.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Register {
    using Address for address;
    
    /* =====================================================================================================================
                                                        Variables
    ===================================================================================================================== */
    mapping(address => string) public _codes;
    
    /* =====================================================================================================================
                                                        Events
    ===================================================================================================================== */
    event SendVerification(address indexed owner, string indexed code);
    
    /* =====================================================================================================================
                                                    Utility Functions
    ===================================================================================================================== */ 
    function verify(string memory code) public  {
        _codes[msg.sender] = code;
        emit SendVerification(msg.sender, code);
    }
    
}