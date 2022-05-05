pragma solidity ^0.5.0;

import "./IExecutableProposal.sol";

contract Proposal is IExecutableProposal {

    event ProposalExecuted(uint proposalId, uint numVotes, uint numTokens);

    function executeProposal(uint proposalId, uint numVotes, uint numTokens) external payable {
        emit ProposalExecuted(proposalId, numVotes, numTokens);
    }

}