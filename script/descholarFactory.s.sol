// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/./descholar.sol";

contract descholarFactory {
    address[] public deployedDescholars;

    event ContractCreated(address contractAddress);

    function createDescholar(address deployer) public {
        address newDescholar = address(new Descholar(deployer));
        deployedDescholars.push(newDescholar);
        emit ContractCreated(newDescholar);
    }

    function getDeployedDescholars() public view returns (address[] memory) {
        return deployedDescholars;
    }
}
