pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "./IQuadraticVoting.sol";

contract QuadraticVoting is IQuadraticVoting {

    address private owner;
    UCMToken private tokenContract;
    uint8 private votingState; // 0 -> closed, 1 -> opened, 2 -> paused
    uint public tokenPrice;
    uint public maxTokens;
    uint private nParticipants;
    mapping(address => bool) public participants;
    uint private nProposals;
    mapping(uint => Proposal) private proposals;
    uint private lastProposalId;


    constructor(uint _tokenPrice, uint _maxTokens) public {
        owner = msg.sender;
        tokenContract = new UCMToken();
        votingState = 0;
        tokenPrice = _tokenPrice;
        maxTokens = _maxTokens;
        nParticipants = 0;
        nProposals = 0;
        lastProposalId = 0;
    }

    //Devuelve el coste cuadrático de meter [votes] votos en la propuesta
    function _calculateVoteCost(uint proposalId, uint votes) view internal returns(uint) {
        uint oldVotes = proposals[proposalId].votes[msg.sender];
        uint oldPrice = oldVotes ** 2;
        uint totalVotes = oldVotes + votes;
        uint totalPrice = totalVotes ** 2;
        return totalPrice - oldPrice;
    }

    //Devuelve el coste cuadrático de meter [votes] votos en la propuesta
    function _calculateWithdrawVote(uint proposalId, uint votes) view internal returns(uint) {
        uint oldVotes = proposals[proposalId].votes[msg.sender];
        uint oldPrice = oldVotes ** 2;
        uint totalVotes = oldVotes - votes;
        uint totalPrice = totalVotes ** 2;
        return oldPrice - totalPrice;
    }

    //Devuelve el umbral de una propuesta
    function _calculateThreshold(uint proposalId) view internal returns(uint) {
        return (2 + (proposals[proposalId].minBudget*10) / (address(this).balance*10))/10 * nParticipants + nProposals;
    }

    //Abre la votación
    function openVoting() checkOwner external payable {
        votingState = 1;
        emit OpenVote();
    }

    //Añade un participante con la compra de tokens incluída
    function addParticipant() checkMinimumPurchaseAmount(msg.value) external payable {
        participants[msg.sender] = true;
        tokenContract.mint(msg.sender, msg.value / tokenPrice);
        nParticipants++;
    }

    //Añade una propuesta
    function addProposal(string calldata title, string calldata description, uint minBudget, address executableProposal) checkParticipant checkVotingOpen external returns(uint) {
        Proposal memory proposal;
        proposal.owner = msg.sender;
        proposal.executableProposal = IExecutableProposal(executableProposal);
        proposal.title = title;
        proposal.description = description;
        proposal.minBudget = minBudget;
        proposal.currentVotes = 0;
        proposal.currentTokens = 0;
        proposal.state = 0;
        lastProposalId++;
        proposals[lastProposalId] = proposal;
        nProposals++;
        return lastProposalId;
    }

    /*
    Cuando se cancela una propuesta (si es posible), se debe:
        -Anotar que ya no está activa.
        -La devolución de todos los tokens correspondientes a los votantes la deben realizar estos.
    */
    function cancelProposal(uint id) checkParticipant checkVotingOpen checkProposalOwner(id) external {
        if (proposals[id].state == 0) {
            proposals[id].state = 1;
            emit CanWithdrawnFromProposal(id);
        }
    }

    //Permite la compra de más tokens por Ether
    function buyTokens() checkParticipant checkMinimumPurchaseAmount(msg.value) external payable {
        tokenContract.mint(msg.sender, msg.value / tokenPrice);
    }

    //Permite la venta de tokens por Ether
    function sellTokens(uint amount) checkParticipant checkTokenAmount(amount) external {
        if (tokenContract.balanceOf(msg.sender) >= amount) {
            tokenContract.burn(msg.sender, amount);
            msg.sender.transfer(amount * tokenPrice);
        }
    }

    //Devuelve la dirección del contrato del token
    function getERC20() view external returns(UCMToken) {
        return tokenContract;
    }

    //Devuelve un array con ids de propuesta pendientes
    function getPendingProposals() checkVotingOpen view external returns(uint[] memory) {
        uint [] memory ids;
        return ids; //TODO
    }

    //Devuelve un array con ids de propuesta aprobadas
    function getApprovedProposals() checkVotingOpen view external returns(uint[] memory) {
        uint [] memory ids;
        return ids; //TODO
    }

    //Devuelve un array con ids de propuesta signaling
    function getSignalingProposals() checkVotingOpen view external returns(uint[] memory) {
        uint [] memory ids;
        return ids; //TODO
    }

    //Devuelve información escasa de una propuesta
    function getProposalInfo(uint id) checkVotingOpen view external returns(string memory title, string memory description, IExecutableProposal executableProposal) {
        return (proposals[id].title, proposals[id].description, proposals[id].executableProposal);
    }

    //Permite votar una propuesta
    function stake(uint id, uint votes) external {
        uint tokenCost = _calculateVoteCost(id, votes);
        if (tokenContract.balanceOf(msg.sender) >= tokenCost) { //Check if exist proposal id
            tokenContract.stakeTransfer(msg.sender, tokenCost);
            proposals[id].currentVotes += votes;

            if (_isProposalApproved(id) && proposals[id].minBudget > 0) {
                _approveProposal(id);
            }
        }
    }

    function _withdrawFromFinanceProposal(uint amount, uint id) internal {
        if (proposals[id].votes[msg.sender] > 0 && proposals[id].votes[msg.sender] >= amount && proposals[id].state != 2) {
            uint tokenAmount = _calculateWithdrawVote(id, amount);
            proposals[id].currentVotes -= proposals[id].votes[msg.sender];
            proposals[id].votes[msg.sender] -= amount;
            proposals[id].currentTokens -= tokenAmount;

            tokenContract.transfer(msg.sender, tokenAmount);
        }
    }

    function _withdrawFromSignalingProposal(uint amount, uint id) internal {
        if (votingState == 1) {
            if (proposals[id].votes[msg.sender] > 0 && proposals[id].votes[msg.sender] >= amount) {
                uint tokenAmount = _calculateWithdrawVote(id, amount);
                proposals[id].currentVotes -= proposals[id].votes[msg.sender];
                proposals[id].votes[msg.sender] -= amount;
                proposals[id].currentTokens -= tokenAmount;

                tokenContract.transfer(msg.sender, tokenAmount);
            }
        } else if (votingState == 2) {
            if (proposals[id].votes[msg.sender] > 0 && proposals[id].votes[msg.sender] >= amount) {
                uint tokenAmount = _calculateWithdrawVote(id, amount);
                proposals[id].votes[msg.sender] -= amount;
                proposals[id].currentTokens -= tokenAmount;

                tokenContract.transfer(msg.sender, tokenAmount);
            }

        }
    }

    //Permite retirar votos de una propuesta, lo que devolverá tokens al usuario
    function withdrawFromProposal(uint amount, uint id) checkParticipant external {
        if (proposals[id].minBudget > 0) _withdrawFromFinanceProposal(amount, id);
        else _withdrawFromSignalingProposal(amount, id);
    }

    //Devuelve si una propuesta está aprobada
    function _isProposalApproved(uint proposalId) view internal returns(bool) {
        Proposal memory proposal = proposals[proposalId];
        return proposal.minBudget < address(this).balance && proposal.currentVotes > _calculateThreshold(proposalId);
    }

    /*
    Cuando se aprueba una propuesta, se debe:
        -Anotar que ya no está activa.
        -Quemar todos los tokens correspondientes a la propuesta si no es Signalin.
        -Ejecutar la función de ejecución del contrato pasado en la creación de la propuesta.
        -Cuando se ejecutas, realizar la transferencia de Ether a este contrato.
    */
    function _approveProposal(uint proposalId) internal {
        proposals[proposalId].state = 2;
        Proposal memory proposal = proposals[proposalId];

        if (proposal.minBudget > 0) {
            tokenContract.burn(address(this), proposal.currentTokens);
        }
        
        proposal.executableProposal.executeProposal.value(proposal.minBudget)(proposalId, proposal.currentVotes, proposal.currentTokens);
    }

    //Refactorizar con métodos de arriba
    function _checkAndExecuteProposal(uint id) internal {
        if (_isProposalApproved(id)) {
            _approveProposal(id);
        }
    }

    //Cierre de votación, necesitamos hacer algo más?
    function closeVoting() checkOwner external payable {
        votingState = 2;
        emit ClosedVote();
    }

    function executeSignaling(uint id) checkParticipant checkProposalOwner(id) external {
        if (votingState == 2) {
            _approveProposal(id);
        }
    }

    modifier checkOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    modifier checkParticipant() {
        require(participants[msg.sender], "Not a participant");
        _;
    }

    modifier checkVotingOpen() {
        require(votingState == 1, "Voting not open");
        _;
    }

    modifier checkProposalOwner(uint id) {
        require(proposals[id].owner == msg.sender, "Unauthorized");
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
}