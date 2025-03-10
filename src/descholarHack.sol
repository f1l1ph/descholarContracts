// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct Hackaton {
    string name;
    string description;
    uint256 prizePool;
    uint256 startDate;
    uint256 endDate;
    address creator;
    address[] judges;
    address[] participants;
    address[] funders;
    address[] teams;
}

struct Team {
    string name;
    address admin;
    address[] members;
    string[] track;
}

contract descholarHack is ReentrancyGuard, Ownable, Pausable {
    // @Featuers:
    // hackathon creator
    // hackathon funder/investor
    // hackathon judges
    // hackathon participants
    // participants can make teams

    // @admin features
    // anyone can/cannot be an invesotr
    // investors are/are not judges
    // hackathon creator can/cannot be a judge

    //TODO: Hackaton is a standalone contract

    bool private investorsAreJudges = false;
    bool private creatorIsJudge = false;
    bool private anyoneCanInvest = false;

    constructor() Ownable(msg.sender) {}

    Hackaton[] private hackathons;

    function createHackathon(
        string memory _name,
        string memory _description,
        uint256 _prize,
        uint256 _startDate,
        uint256 _endDate
    ) public payable {
        Hackaton memory newHackaton = Hackaton({
            name: _name,
            description: _description,
            prizePool: _prize,
            startDate: _startDate,
            endDate: _endDate,
            creator: msg.sender,
            judges: new address[](0),
            participants: new address[](0),
            funders: new address[](0),
            teams: new address[](0)
        });
        require(_startDate < _endDate, "Start date must be less than end date");
        require(msg.value >= _prize, "Insufficient funds");

        hackathons.push(newHackaton);
    }

    function fundHackaton(uint256 _hackatonId) public payable {
        // anyone can fund a hackathon
        Hackaton storage hackaton = hackathons[_hackatonId];
        hackaton.funders.push(msg.sender);
    }

    function joinHackaton(uint256 _hackatonId) public {
        //judges/investors/creator cannot join
        Hackaton storage hackaton = hackathons[_hackatonId];
        hackaton.participants.push(msg.sender);
    }

    function getHackathons() public view returns (Hackaton[] memory) {
        return hackathons;
    }
}
