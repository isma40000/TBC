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

    uint private closedate;

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

    function _calculateVoteCost(uint proposalId, uint votes) view internal returns(uint) {
        uint oldVotes = proposals[proposalId].votes[msg.sender];
        uint oldPrice = oldVotes ** 2;
        uint totalVotes = oldVotes + votes;
        uint totalPrice = totalVotes ** 2;
        return totalPrice - oldPrice;
    }

    function _calculateWithdrawVote(uint proposalId, uint votes) view internal returns(uint) {
        uint oldVotes = proposals[proposalId].votes[msg.sender];
        uint oldPrice = oldVotes ** 2;
        uint totalVotes = oldVotes - votes;
        uint totalPrice = totalVotes ** 2;
        return oldPrice - totalPrice;
    }

    function _calculateThreshold(uint proposalId) view internal returns(uint) {
        return nProposals + nParticipants * (2 + (proposals[proposalId].budget*10) / (address(this).balance*10))/10;
    }

    function _clear() internal {
        nProposals = 0;
        initialProposalId = lastProposalId + 1;
        delete pendingProposalsIds;
        delete approvedProposalsIds;
        delete signalingProposalsIds;
    }

    function openVoting() checkOwner checkCanOpenVoting external payable {
        votingState = QuadraticVotingState.OPEN;
        closedate=0;
        _clear();
        emit OpenVote();
    }

    function addParticipant() checkMinimumPurchaseAmount(msg.value) checkNonParticipant checkMaxTokens(msg.value / tokenPrice) external payable {
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
        if (budget != 0) {
            proposal.posArrays = pendingProposalsIds.length;
            pendingProposalsIds.push(lastProposalId);
        } else {
            proposal.posArrays = signalingProposalsIds.length;
            signalingProposalsIds.push(lastProposalId);
        }
        proposals[lastProposalId] = proposal;
        nProposals++;
        return lastProposalId;
    }

    function cancelProposal(uint id) checkParticipant checkValidProposal(id) checkOpenVoting checkProposalOwner(id) checkEnabledProposal(id) external {
        proposals[id].state = ProposalState.DISABLED;

        if (proposals[id].budget != 0) {
            uint lastPendingProposalId = pendingProposalsIds[pendingProposalsIds.length - 1];
            uint posToDelete = proposals[id].posArrays;
            proposals[lastPendingProposalId].posArrays = posToDelete;
            pendingProposalsIds[posToDelete] = lastPendingProposalId;
            pendingProposalsIds.pop();
        } else {
            uint lastSignalingProposalId = signalingProposalsIds[signalingProposalsIds.length - 1];
            uint posToDelete = proposals[id].posArrays;
            proposals[lastSignalingProposalId].posArrays = posToDelete;
            signalingProposalsIds[posToDelete] = lastSignalingProposalId;
            signalingProposalsIds.pop();
        }

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
    function getTokensNumber() view external returns(uint) {
        return tokenContract.balanceOf(msg.sender);
    }
    function getPendingProposals() checkOpenVoting view external returns(uint[] memory) {
        return pendingProposalsIds;
    }

    function getApprovedProposals() checkOpenVoting view external returns(uint[] memory) {
        return approvedProposalsIds;
    }

    function getSignalingProposals() checkOpenVoting view external returns(uint[] memory) {
        return signalingProposalsIds;
    }

    function getProposalInfo(uint id) checkOpenVoting view external returns(string memory title, string memory description, IExecutableProposal executableProposal) {
        return (proposals[id].title, proposals[id].description, proposals[id].executableProposal);
    }

    function stake(uint id, uint votes) checkParticipant checkValidProposal(id) checkEnabledProposal(id) checkTokenAmount(_calculateVoteCost(id, votes)) checkAllowanceTokensAmount(_calculateVoteCost(id, votes)) external {
        uint tokenCost = _calculateVoteCost(id, votes);
        tokenContract.transferFrom(msg.sender, address(this), tokenCost);
        proposals[id].votesAmount += votes;
        proposals[id].votes[msg.sender] += votes;
        proposals[id].tokensAmount += tokenCost;
        if (proposals[id].budget > 0) {
            _checkAndExecuteProposal(id);
        }
    }

    function _withdrawFromFinanceProposal(uint amount, uint id) internal {
        uint tokenAmount = _calculateWithdrawVote(id, amount);
        proposals[id].votesAmount -= amount;
        proposals[id].votes[msg.sender] -= amount;
        proposals[id].tokensAmount -= tokenAmount;
        tokenContract.transfer(msg.sender, tokenAmount);
    }

    function _withdrawFromSignalingProposal(uint amount, uint id) internal {
        if (votingState == QuadraticVotingState.OPEN) {
            uint tokenAmount = _calculateWithdrawVote(id, amount);
            proposals[id].votesAmount -= amount;
            proposals[id].votes[msg.sender] -= amount;
            proposals[id].tokensAmount -= tokenAmount;
            tokenContract.transfer(msg.sender, tokenAmount);
        } else if (votingState == QuadraticVotingState.WAITING) {
            uint tokenAmount = _calculateWithdrawVote(id, amount);
            /*
            Waiting es el estado de paso antes de reiniciar, cuando se permite a los participantes retirar sus votos de signaling.
            Ojo que esto es el mapping de votos, la variable votesAmount se deja como está.
            Necesitamos quitarlo del mapping por que es la forma de saber cuantos votos realizó el participante. Puede retirar hoy 2 votos y mañana 4, si quiere.
            */
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
    
    function _approveProposal(uint proposalId) internal {
        nProposals--;
        proposals[proposalId].state = ProposalState.APPROVED;
        Proposal memory proposal = proposals[proposalId];

        if (proposal.budget > 0) {
            tokenContract.burn(address(this), proposal.tokensAmount);
        }

        if (proposals[proposalId].budget>0) {
            uint lastPendingProposalId = pendingProposalsIds[pendingProposalsIds.length-1];
            uint posToDelete = proposals[proposalId].posArrays;
            proposals[lastPendingProposalId].posArrays = posToDelete;
            pendingProposalsIds[posToDelete]= lastPendingProposalId;
            pendingProposalsIds.pop();
            proposals[proposalId].posArrays = approvedProposalsIds.length;
            approvedProposalsIds.push(proposalId);
        } else {
            uint lastPendingProposalId = signalingProposalsIds[signalingProposalsIds.length-1];
            uint posToDelete = proposals[proposalId].posArrays;
            proposals[lastPendingProposalId].posArrays = posToDelete;
            signalingProposalsIds[posToDelete]= lastPendingProposalId;
            signalingProposalsIds.pop();
        }
        
        proposal.executableProposal.executeProposal.gas(100000).value(proposal.budget)(proposalId, proposal.votesAmount, proposal.tokensAmount);
    }

    function _checkAndExecuteProposal(uint id) internal {
        if (_isProposalApproved(id)) {
            _approveProposal(id);
        }
    }

    function closeVoting() checkOwner checkOpenVoting external {
        votingState = QuadraticVotingState.WAITING;
        address(uint160(owner)).transfer(address(this).balance);
        closedate = now;
        emit WaitingVote();
    }

    function executeSignaling(uint id) checkParticipant checkValidProposal(id) checkProposalOwner(id) checkSignalingProposal(id) checkWaitingVoting external {
        _approveProposal(id);
    }

    modifier checkOwner() {
        require(msg.sender == owner, "Not Owner: Unauthorized");
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

    modifier checkOpenVoting() {
        require(votingState == QuadraticVotingState.OPEN, "Voting not open");
        _;
    }

    modifier checkWaitingVoting() {
        require(votingState == QuadraticVotingState.WAITING, "Voting not waiting");
        _;
    }

    modifier checkCanOpenVoting() {
        require((votingState == QuadraticVotingState.WAITING && closedate + 604800 < now) || votingState == QuadraticVotingState.CLOSED, "Voting cannot open");
        _;//604800 = una semana en segundos
    }

    modifier checkProposalOwner(uint id) {
        require(proposals[id].owner == msg.sender, "Not Proposal Owner: Unauthorized");
        _;
    }

    modifier checkVotes(uint id, uint votes) {
        require(proposals[id].votes[msg.sender] >= votes, "Not Enough Votes: Unauthorized");
        _;
    }

    modifier checkMinimumPurchaseAmount(uint amount) {
        require(amount >= tokenPrice, "Invalid purchase amount");
        _;
    }

    modifier checkTokenAmount(uint amount) {
        require(amount <= tokenContract.balanceOf(msg.sender), "Invalid amount");
        _;
    }

    modifier checkAllowanceTokensAmount(uint amount) {
        require(amount <= tokenContract.allowance(msg.sender, address(this)), "Invalid allowance amount");
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

    modifier checkNonDisabledProposal(uint id) {
        require(proposals[id].state != ProposalState.DISABLED, "Proposal disabled");
        _;
    }

    modifier checkSignalingProposal(uint id) {
        require(proposals[id].budget == 0, "Proposal non signaling");
        _;
    }
}