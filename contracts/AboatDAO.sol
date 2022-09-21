// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./libraries/TransferHelper.sol";
import "./chains/kardiachain/AboatToken.sol";
import "./chains/kardiachain/MasterEntertainer.sol";
import "./libraries/TimeLock.sol";

contract AboatDAO is Ownable, TimeLock, ReentrancyGuard {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    struct PendingProposal {
        uint256 _id;
        uint256 _paidFee;
        uint256 _openTime;
        mapping(address => uint256) _userVotings;
        mapping(address => uint32) _userVotingTypes;
        mapping(uint32 => uint256) _typeVotings;
    }

    struct Proposal {
        uint256 _id;
        uint256 _paidFee;
        uint16 _functionId;
        uint256 _openTime;
        uint _functionParameter;
        uint32 _proposalType; // 0 = Breaking Change | 1 = New Feature | 2 = Enhancement | 3 = Function Trigger
        uint256 _yesVote;
        uint256 _noVote;
        mapping(address => UserVote) _userVotes;
    }

    struct UserVote {
        bool _agreedProposal;
        uint256 _votingPower;
    }

    uint256 _proposalTypeVotingDays = 2 days;
    uint256 _proposalVotingDays = 5 days;
    Counters.Counter private _proposalCount;
    uint256 _proposalFee = 100000 ether;
    AboatToken _token;
    MasterEntertainer _masterEntertainer;
    mapping(uint256 => Proposal) public _proposals;
    mapping(uint256 => PendingProposal) public _pendingProposals;
    mapping(string => uint16) _functions;

    event OpenedProposal(address proposer, uint256 proposalId);
    event TriggeredFunction(uint256 proposal, string functionName);    
    event VotedForPendingProposal(address votee, uint256 proposalId, uint32 voteType);

    constructor(AboatToken token, MasterEntertainer masterEntertainer) {
        _token = token;
        _masterEntertainer = masterEntertainer;
        _functions["maxAccBalance"] = 1;
        _functions["maxTransactionQuantity"] = 2;
        _functions["activateHighFee"] = 3;
        _functions["deactivateHighFee"] = 4;
    }

    function getUserVotingPower(address user) public view returns (uint256) {
        uint256 overallBalance = _masterEntertainer.getBalanceOf(user, 0);
        uint256 thirtyDayBalance = _masterEntertainer.getBalanceOf(user, 30);
        uint256 ninetyDayBalance = _masterEntertainer.getBalanceOf(user, 90);
        uint256 halfYearBalance = _masterEntertainer.getBalanceOf(user, 180);
        uint256 oneYearBalance = _masterEntertainer.getBalanceOf(user, 360);
        return overallBalance.add(thirtyDayBalance).add(ninetyDayBalance).add(halfYearBalance).add(oneYearBalance);
    }

    function proposeFunctionTrigger(string memory functionTrigger, uint256 value) public nonReentrant {
        require(_token.balanceOf(msg.sender) >= _proposalFee, "ABOAT:proposeFunctionTrigger::Not enough funds to propose");
        uint256 currentProposalId = _proposalCount.current();
        _proposalCount.increment();
        Proposal storage proposal = _proposals[currentProposalId];
        proposal._id = currentProposalId;
        proposal._functionId = _functions[functionTrigger];
        proposal._proposalType = 3;
        UserVote storage userVote = proposal._userVotes[msg.sender];
        userVote._agreedProposal = true;
        userVote._votingPower = getUserVotingPower(msg.sender);
        proposal._yesVote = userVote._votingPower;
        proposal._paidFee = _proposalFee;
        proposal._functionParameter = value;
        proposal._openTime = block.timestamp;
        TransferHelper.safeTransferFrom(address(_token), msg.sender, address(this), _proposalFee);
        emit OpenedProposal(msg.sender, currentProposalId);
    }

    function propose(uint32 suggestedType) public nonReentrant {
        require(_token.balanceOf(msg.sender) >= _proposalFee, "ABOAT:propose::Not enough funds to propose");
        uint256 currentProposalId = _proposalCount.current();
        _proposalCount.increment();
        PendingProposal storage proposal = _pendingProposals[currentProposalId];
        proposal._id = currentProposalId;
        uint256 userVotingPower = getUserVotingPower(msg.sender);
        proposal._typeVotings[suggestedType] = userVotingPower;
        proposal._userVotings[msg.sender] = userVotingPower;
        proposal._userVotingTypes[msg.sender] = suggestedType;
        proposal._paidFee = _proposalFee;
        proposal._openTime = block.timestamp;
        TransferHelper.safeTransferFrom(address(_token), msg.sender, address(this), _proposalFee);
        emit OpenedProposal(msg.sender, currentProposalId);
    }

    function votePending(uint256 id, uint32 voteType) public nonReentrant {
        require(_pendingProposals[id]._openTime > 0, "ABOAT:votePending::Proposal does not exist!");
        require(_pendingProposals[id]._openTime + _proposalTypeVotingDays < block.timestamp, "ABOAT:votePending::Proposal has ended!");
        uint256 userVotingPower = getUserVotingPower(msg.sender);
        require(userVotingPower > 0, "ABOAT:votePending::User Voting Power needs to be higher than 0!");
        uint256 currentUserVote = _pendingProposals[id]._userVotings[msg.sender];
        if(currentUserVote > 0) {
            uint256 currentUserVoteAmount = _pendingProposals[id]._userVotings[msg.sender];
            uint32 currentUserVoteType = _pendingProposals[id]._userVotingTypes[msg.sender];
            _pendingProposals[id]._typeVotings[currentUserVoteType] = _pendingProposals[id]._typeVotings[currentUserVoteType].sub(currentUserVoteAmount);
        }
        _pendingProposals[id]._typeVotings[voteType] = _pendingProposals[id]._typeVotings[voteType].add(userVotingPower);
        _pendingProposals[id]._userVotingTypes[msg.sender] = voteType;
        _pendingProposals[id]._userVotings[msg.sender] = userVotingPower;
        emit VotedForPendingProposal(msg.sender, id, voteType);
    }

    function utfStringLength(string memory str) pure internal returns (uint length) {
        uint i=0;
        bytes memory string_rep = bytes(str);

        while (i<string_rep.length)
        {
            if (string_rep[i]>>7==0)
                i+=1;
            else if (string_rep[i]>>5==bytes1(uint8(0x6)))
                i+=2;
            else if (string_rep[i]>>4==bytes1(uint8(0xE)))
                i+=3;
            else if (string_rep[i]>>3==bytes1(uint8(0x1E)))
                i+=4;
            else
                //For safety
                i+=1;

            length++;
        }
    }

    function compareStrings(string memory a, string memory b) public view returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}