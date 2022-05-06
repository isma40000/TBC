pragma solidity ^0.5.0;

import "./IQuadraticVoting.sol";

contract QuadraticVoting is IQuadraticVoting {

    address private owner;
    UCMToken private tokenContract;
    QuadraticVotingState private votingState;
    uint private tokenPrice;
    uint private maxTokens;

    uint private nParticipants;
    mapping(address => bool) private participants;

    uint private nProposals;
    mapping(uint => Proposal) private proposals;
    uint private initialProposalId;
    uint private lastProposalId;

    uint [] private pendingProposalsIds;
    uint [] private approvedProposalsIds;
    uint [] private signalingProposalsIds;


    constructor(uint _tokenPrice, uint _maxTokens) public {
        owner = msg.sender;
        tokenContract = new UCMToken();
        votingState = QuadraticVotingState.CLOSED;
        tokenPrice = _tokenPrice;
        maxTokens = _maxTokens;

        nParticipants = 0;
        nProposals = 0;
        initialProposalId = 1;
        lastProposalId = 0;
    }

    //Devuelve el coste cuadrático de meter [votes] votos en la propuesta
    function _calculateVoteCost(uint proposalId, uint votes) view private returns(uint) {
        uint oldVotes = proposals[proposalId].votes[msg.sender];
        uint oldPrice = oldVotes ** 2;
        uint totalVotes = oldVotes + votes;
        uint totalPrice = totalVotes ** 2;
        return totalPrice - oldPrice;
    }

    //Devuelve el coste cuadrático de meter [votes] votos en la propuesta
    function _calculateWithdrawVote(uint proposalId, uint votes) view private returns(uint) {
        uint oldVotes = proposals[proposalId].votes[msg.sender];
        uint oldPrice = oldVotes ** 2;
        uint totalVotes = oldVotes - votes;
        uint totalPrice = totalVotes ** 2;
        return oldPrice - totalPrice;
    }

    //Devuelve el umbral de una propuesta
    function _calculateThreshold(uint proposalId) view private returns(uint) {
        return (2 + (proposals[proposalId].budget*10) / (address(this).balance*10))/10 * nParticipants + nProposals;
    }

    function _clear() private {
        nProposals = 0;
        initialProposalId = lastProposalId + 1;
    }

    function openVoting() checkOwner checkCanOpenVoting external payable {
        votingState = QuadraticVotingState.OPEN;
        _clear();
        emit OpenVote();
    }

    function addParticipant() checkMinimumPurchaseAmount(msg.value) checkNonParticipant external payable {
        participants[msg.sender] = true;
        tokenContract.mint(msg.sender, msg.value / tokenPrice);
        nParticipants++;
    }

    function addProposal(string calldata title, string calldata description, uint budget, address executableProposal) checkParticipant checkOpenVoting external returns(uint) {
        Proposal memory proposal;
        proposal.owner = msg.sender;
        proposal.executableProposal = IExecutableProposal(executableProposal);
        proposal.title = title;
        proposal.description = description;
        proposal.budget = budget;
        proposal.votesAmount = 0;
        proposal.tokensAmount = 0;
        proposal.state = ProposalState.ENABLED;
        lastProposalId++;
        proposals[lastProposalId] = proposal;
        nProposals++;
        return lastProposalId;
    }

    function cancelProposal(uint id) checkParticipant checkOpenVoting checkProposalOwner(id) checkEnabledProposal(id) external {
        proposals[id].state = ProposalState.DISABLED;
        emit CanWithdrawnFromProposal(id);
    }

    function buyTokens() checkParticipant checkMinimumPurchaseAmount(msg.value) checkMaxTokens(msg.value / tokenPrice) external payable {
        tokenContract.mint(msg.sender, msg.value / tokenPrice);
    }

    function sellTokens(uint amount) checkParticipant checkTokenAmount(amount) external {
        tokenContract.burn(msg.sender, amount);
        msg.sender.transfer(amount * tokenPrice);
    }

    function getERC20() view external returns(UCMToken) {
        return tokenContract;
    }

    function getPendingProposals() checkOpenVoting external returns(uint[] memory) {
        delete pendingProposalsIds;

        //Duda ya preguntada a Jesús, tiene coste lineal respecto al número de propuestas actuales
        for (uint id = initialProposalId; id <= lastProposalId; id++) {
            if (proposals[id].state == ProposalState.ENABLED && proposals[id].budget > 0) {
                pendingProposalsIds.push(id);
            }
        }

        return pendingProposalsIds;
    }

    function getApprovedProposals() checkOpenVoting external returns(uint[] memory) {
        delete approvedProposalsIds;

        //Duda ya preguntada a Jesús, tiene coste lineal respecto al número de propuestas actuales
        for (uint id = initialProposalId; id <= lastProposalId; id++) {
            if (proposals[id].state == ProposalState.APPROVED && proposals[id].budget > 0) {
                approvedProposalsIds.push(id);
            }
        }

        return approvedProposalsIds;
    }

    function getSignalingProposals() checkOpenVoting external returns(uint[] memory) {
        delete signalingProposalsIds;

        //Duda ya preguntada a Jesús, tiene coste lineal respecto al número de propuestas actuales
        for (uint id = initialProposalId; id <= lastProposalId; id++) {
            if (proposals[id].state != ProposalState.DISABLED && proposals[id].budget == 0) {
                signalingProposalsIds.push(id);
            }
        }

        return signalingProposalsIds;
    }

    function getProposalInfo(uint id) checkOpenVoting view external returns(string memory title, string memory description, IExecutableProposal executableProposal) {
        return (proposals[id].title, proposals[id].description, proposals[id].executableProposal);
    }

    function stake(uint id, uint votes) checkParticipant checkValidProposal(id) checkEnabledProposal(id) checkTokenAmount(_calculateVoteCost(id, votes)) external {
        uint tokenCost = _calculateVoteCost(id, votes);
        tokenContract.transfer(address(this), tokenCost);
        proposals[id].votesAmount += votes;
        proposals[id].tokensAmount += tokenCost;
        if (proposals[id].budget > 0) {
            _checkAndExecuteProposal(id);
        }
    }

    function _withdrawFromFinanceProposal(uint amount, uint id) checkValidProposal(id) checkNonDisabledProposal(id) private {
        uint tokenAmount = _calculateWithdrawVote(id, amount);
        proposals[id].votesAmount -= amount;
        proposals[id].votes[msg.sender] -= amount;
        proposals[id].tokensAmount -= tokenAmount;
        tokenContract.transfer(msg.sender, tokenAmount);
    }

    function _withdrawFromSignalingProposal(uint amount, uint id)  private {
        if (votingState == QuadraticVotingState.OPEN) {
            uint tokenAmount = _calculateWithdrawVote(id, amount);
            proposals[id].votesAmount -= amount;
            proposals[id].votes[msg.sender] -= amount;
            proposals[id].tokensAmount -= tokenAmount;
            tokenContract.transfer(msg.sender, tokenAmount);
        } else if (votingState == QuadraticVotingState.WAITING) {
            uint tokenAmount = _calculateWithdrawVote(id, amount);
            proposals[id].votes[msg.sender] -= amount;
            tokenContract.transfer(msg.sender, tokenAmount);
        }
    }

    function withdrawFromProposal(uint amount, uint id) checkParticipant checkValidProposal(id) checkVotes(id, amount) external {
        if (proposals[id].budget > 0) _withdrawFromFinanceProposal(amount, id);
        else _withdrawFromSignalingProposal(amount, id);
    }

    function _isProposalApproved(uint proposalId) view internal returns(bool) {
        Proposal memory proposal = proposals[proposalId];
        return proposal.budget < address(this).balance && proposal.votesAmount > _calculateThreshold(proposalId);
    }
    
    function _approveProposal(uint proposalId) private {
        nProposals--;
        proposals[proposalId].state = ProposalState.APPROVED;
        Proposal memory proposal = proposals[proposalId];

        if (proposal.budget > 0) {
            tokenContract.burn(address(this), proposal.tokensAmount);
        }
        
        proposal.executableProposal.executeProposal.value(proposal.budget)(proposalId, proposal.votesAmount, proposal.tokensAmount);
    }

    function _checkAndExecuteProposal(uint id) internal {
        if (_isProposalApproved(id)) {
            _approveProposal(id);
        }
    }

    function closeVoting() checkOwner external {
        votingState = QuadraticVotingState.WAITING;
        emit WaitingVote();
    }

    function executeSignaling(uint id) checkParticipant checkProposalOwner(id) checkWaitingVoting external {
        _approveProposal(id);
    }

    modifier checkOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    modifier checkParticipant() {
        require(participants[msg.sender], "Not a participant");
        _;
    }

    modifier checkNonParticipant() {
        require(!participants[msg.sender], "Already participant");
        _;
    }

    modifier checkClosedVoting() {
        require(votingState == QuadraticVotingState.CLOSED, "Voting not closed");
        _;
    }

    modifier checkOpenVoting() {
        require(votingState == QuadraticVotingState.OPEN, "Voting not open");
        _;
    }

    modifier checkWaitingVoting() {
        require(votingState == QuadraticVotingState.WAITING, "Voting not waiting");
        _;
    }

    modifier checkCanOpenVoting() {
        require(votingState == QuadraticVotingState.WAITING || votingState == QuadraticVotingState.CLOSED, "Voting cannot open");
        _;
    }

    modifier checkProposalOwner(uint id) {
        require(proposals[id].owner == msg.sender, "Unauthorized");
        _;
    }

    modifier checkVotes(uint id, uint votes) {
        require(proposals[id].votes[msg.sender] >= votes, "Unauthorized");
        _;
    }

    modifier checkMinimumPurchaseAmount(uint amount) {
        require(amount >= tokenPrice, "Invalid purchase amount");
        _;
    }

    modifier checkTokenAmount(uint amount) {
        require(amount >= tokenContract.balanceOf(msg.sender), "Invalid amount");
        _;
    }

    modifier checkMaxTokens(uint amount) {
        require(tokenContract.totalSupply() + amount < maxTokens , "The maximum number of tokens has been generated");
        _;
    }

    modifier checkValidProposal(uint id) {
        require(initialProposalId <= id && id <= lastProposalId, "Proposal id not valid");
        _;
    }

    modifier checkEnabledProposal(uint id) {
        require(proposals[id].state == ProposalState.ENABLED, "Proposal not enabled");
        _;
    }

    modifier checkDisabledProposal(uint id) {
        require(proposals[id].state == ProposalState.DISABLED, "Proposal not disabled");
        _;
    }

    modifier checkApprovedProposal(uint id) {
        require(proposals[id].state == ProposalState.APPROVED, "Proposal not approved");
        _;
    }

    modifier checkNonDisabledProposal(uint id) {
        require(proposals[id].state != ProposalState.DISABLED, "Proposal disabled");
        _;
    }
}