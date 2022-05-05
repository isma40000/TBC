pragma solidity ^0.5.0;

import "./UCMToken.sol";
import "./IExecutableProposal.sol";

interface IQuadraticVoting {

    event OpenVote();
    event CanWithdrawnFromProposal(uint proposalId);
    event ClosedVote();

    struct Proposal {
        address owner;
        IExecutableProposal executableProposal;
        string title;
        string description;
        uint minBudget; //Amount in Ether
        uint currentVotes;
        uint currentTokens;
        mapping(address => uint) votes;
        uint8 state; // 0 -> enabled, 1 -> disabled, 2 -> aprobed
    }

    function openVoting() external payable;
    function addParticipant() external payable;
    function addProposal(string calldata title, string calldata description, uint minBudget, address executableProposal) external returns(uint);
    function cancelProposal(uint id) external;
    function buyTokens() external payable;
    function sellTokens(uint amount) external;
    function getERC20() view external returns(UCMToken);
    function getPendingProposals() view external returns(uint[] memory);
    function getApprovedProposals() view external returns(uint[] memory);
    function getSignalingProposals() view external returns(uint[] memory);
    function stake(uint id, uint votes) external;
    function withdrawFromProposal(uint amount, uint id) external;
    function closeVoting() external payable;
    function executeSignaling(uint id) external;
}