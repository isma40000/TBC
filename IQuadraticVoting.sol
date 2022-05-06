pragma solidity ^0.5.0;

import "./UCMToken.sol";
import "./IExecutableProposal.sol";

interface IQuadraticVoting {

    event OpenVote();
    event WaitingVote();
    event CanWithdrawnFromProposal(uint proposalId);

    enum QuadraticVotingState { CLOSED, OPEN, WAITING }

    enum ProposalState { ENABLED, DISABLED, APPROVED }

    struct Proposal {
        address owner;
        IExecutableProposal executableProposal;
        string title;
        string description;
        uint budget;
        uint votesAmount;
        uint tokensAmount;
        mapping(address => uint) votes;
        ProposalState state;
        uint posArrays;
    }

    function openVoting() external payable;
    function addParticipant() external payable;
    function addProposal(string calldata title, string calldata description, uint minBudget, address executableProposal) external returns(uint);
    function cancelProposal(uint id) external;
    function buyTokens() external payable;
    function sellTokens(uint amount) external;
    function getERC20() view external returns(UCMToken);
    function getPendingProposals() external returns(uint[] memory);
    function getApprovedProposals() external returns(uint[] memory);
    function getSignalingProposals() external returns(uint[] memory);
    function stake(uint id, uint votes) external;
    function withdrawFromProposal(uint amount, uint id) external;
    function closeVoting() external;
    function executeSignaling(uint id) external;
}