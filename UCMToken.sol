pragma solidity ^0.5.0;

import "./openzeppelin/ERC20.sol";
import "./openzeppelin/ERC20Detailed.sol";
import "./openzeppelin/roles/MinterRole.sol";

contract UCMToken is ERC20, ERC20Detailed, MinterRole {

    address private owner;

    constructor() ERC20Detailed("UCM", "UCM", 0) public {
        owner = msg.sender;
    }

    function mint(address account, uint amount) external onlyMinter {
        _mint(account, amount);
    }

    function burn(address account, uint amount) external onlyMinter {
        _burn(account, amount);
    }

    modifier checkOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }
}