// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Scholarship, ApplicationStatus, Application} from "./descholar.utilities.sol";

contract Descholar is ReentrancyGuard, Ownable, Pausable {
    // Constructor
    constructor(address initialOwner) Ownable(initialOwner) {}

    //add custom errors

    // Events
    event ScholarshipCreated(uint256 indexed scholarshipId, address indexed creator, uint256 totalAmount);
    event ApplicationSubmitted(uint256 indexed scholarshipId, uint256 indexed applicationId, address applicant);
    event ApplicationStatusChanged(uint256 indexed applicationId, ApplicationStatus status);
    event GrantAwarded(uint256 indexed scholarshipId, address indexed recipient, uint256 amount);
    event ScholarshipCancelled(uint256 indexed scholarshipId, string reason, uint256 refundAmount);
    event ScholarshipWithdrawn(uint256 indexed scholarshipId, uint256 refundAmount);

    // State variables
    Scholarship[] public scholarships;
    Application[] public applications;

    // Mappings for efficient queries
    mapping(address => uint256[]) public userApplications;
    mapping(address => uint256[]) public userScholarships;
    mapping(uint256 => uint256[]) public scholarshipApplications;
    mapping(uint256 => mapping(address => bool)) public hasApplied;

    // Constants
    uint256 public constant MIN_GRANT_AMOUNT = 0.01 ether; // 10^16 wei (0.01 ETH)
    uint256 public constant MAX_GRANTS = 1000;

    // Modifiers
    modifier validScholarship(uint256 scholarshipId) {
        require(scholarshipId < scholarships.length, "Invalid scholarship ID");
        _;
    }

    modifier scholarshipActive(uint256 scholarshipId) {
        require(scholarships[scholarshipId].active, "Scholarship not active");
        require(block.timestamp < scholarships[scholarshipId].endDate, "Scholarship expired");
        _;
    }

    modifier onlyScholarshipCreatorOrAdmin(uint256 scholarshipId) {
        require(
            msg.sender == scholarships[scholarshipId].creator || msg.sender == owner(),
            "Not scholarship creator or admin"
        );
        _;
    }

    // Main functions
    function postScholarship(
        string calldata name,
        string calldata creatorName,
        string calldata details,
        uint256 grantAmount,
        uint256 numberOfGrants,
        uint256 endDate,
        address tokenId
    ) external payable whenNotPaused nonReentrant {
        require(bytes(name).length > 0, "Empty name");
        require(bytes(creatorName).length > 0, "Empty creator name");
        require(bytes(details).length > 0, "Empty details");
        require(bytes(name).length <= 100, "Name too long");
        require(bytes(creatorName).length <= 100, "Creator name too long");
        require(bytes(details).length <= 2500, "Details too long");
        require(grantAmount >= MIN_GRANT_AMOUNT, "Grant amount too low");
        require(numberOfGrants > 0 && numberOfGrants <= MAX_GRANTS, "Invalid number of grants");
        require(endDate > block.timestamp, "Invalid end date");

        uint256 totalAmount = grantAmount * numberOfGrants;

        EnsurePostScholarshipTokenTransfer(tokenId, totalAmount);

        uint256 scholarshipId = scholarships.length;
        scholarships.push(
            Scholarship({
                id: scholarshipId,
                name: name,
                creatorName: creatorName,
                details: details,
                grantAmount: grantAmount,
                remainingGrants: numberOfGrants,
                totalGrants: numberOfGrants,
                endDate: endDate,
                creator: msg.sender,
                active: true,
                createdAt: block.timestamp,
                isCancelled: false,
                cancellationReason: "",
                cancelledAt: 0,
                tokenId: tokenId
            })
        );

        userScholarships[msg.sender].push(scholarshipId);
        emit ScholarshipCreated(scholarshipId, msg.sender, totalAmount);
    }

    function applyForScholarship(uint256 scholarshipId, string calldata name, string calldata details)
        external
        whenNotPaused
        nonReentrant
        validScholarship(scholarshipId)
        scholarshipActive(scholarshipId)
    {
        require(bytes(name).length > 0, "Empty name");
        require(bytes(details).length > 0, "Empty details");
        require(!hasApplied[scholarshipId][msg.sender], "Already applied");
        require(bytes(name).length <= 100, "Name too long");
        require(bytes(details).length <= 2500, "Details too long");

        uint256 applicationId = applications.length;
        applications.push(
            Application({
                id: applicationId,
                scholarshipId: scholarshipId,
                applicant: msg.sender,
                name: name,
                details: details,
                status: ApplicationStatus.Applied,
                appliedAt: block.timestamp
            })
        );

        hasApplied[scholarshipId][msg.sender] = true;
        userApplications[msg.sender].push(applicationId);
        scholarshipApplications[scholarshipId].push(applicationId);
        emit ApplicationSubmitted(scholarshipId, applicationId, msg.sender);
    }

    function approveApplication(uint256 scholarshipId, uint256 applicationId)
        external
        whenNotPaused
        nonReentrant
        validScholarship(scholarshipId)
        onlyScholarshipCreatorOrAdmin(scholarshipId)
    {
        Application storage application = applications[applicationId];
        require(application.scholarshipId == scholarshipId, "Application mismatch");
        require(application.status == ApplicationStatus.Applied, "Invalid application status");
        require(application.id < applications.length, "Invalid application ID");

        Scholarship storage scholarship = scholarships[scholarshipId];
        require(scholarship.remainingGrants > 0, "No remaining grants");

        application.status = ApplicationStatus.Approved;
        scholarship.remainingGrants--;

        if (scholarship.tokenId == address(0)) {
            (bool success, ) = payable(application.applicant).call{value: scholarship.grantAmount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 token = IERC20(scholarship.tokenId);
            SafeERC20.safeTransfer(token, application.applicant, scholarship.grantAmount);
        }

        emit ApplicationStatusChanged(applicationId, ApplicationStatus.Approved);
        emit GrantAwarded(scholarshipId, application.applicant, scholarship.grantAmount);
    }

    function rejectApplication(uint256 scholarshipId, uint256 applicationId)
        external
        whenNotPaused
        nonReentrant
        validScholarship(scholarshipId)
        onlyScholarshipCreatorOrAdmin(scholarshipId)
    {
        Application storage application = applications[applicationId];
        require(application.scholarshipId == scholarshipId, "Application mismatch");
        require(application.status == ApplicationStatus.Applied, "Invalid application status");
        require(application.id < applications.length, "Invalid application ID");

        application.status = ApplicationStatus.Rejected;

        emit ApplicationStatusChanged(applicationId, ApplicationStatus.Rejected);
    }

    function cancelScholarship(uint256 scholarshipId, string calldata reason)
        external
        whenNotPaused
        nonReentrant
        validScholarship(scholarshipId)
        onlyScholarshipCreatorOrAdmin(scholarshipId)
    {
        Scholarship storage scholarship = scholarships[scholarshipId];
        require(scholarship.active, "Scholarship already inactive");
        require(!scholarship.isCancelled, "Scholarship already cancelled");
        require(bytes(reason).length > 0, "Must provide cancellation reason");
        require(bytes(reason).length <= 2500, "Cancellation reason too long");

        uint256 refundAmount = scholarship.grantAmount * scholarship.remainingGrants;

        scholarship.active = false;
        scholarship.remainingGrants = 0;
        scholarship.isCancelled = true;
        scholarship.cancellationReason = reason;
        scholarship.cancelledAt = block.timestamp;

        if (scholarship.tokenId == address(0)) {
            payable(scholarship.creator).transfer(refundAmount);
        } else {
            IERC20 token = IERC20(scholarship.tokenId);
            SafeERC20.safeTransfer(token, scholarship.creator, refundAmount);
        }

        emit ScholarshipCancelled(scholarshipId, reason, refundAmount);
    }

    function withdrawExpiredScholarship(uint256 scholarshipId)
        external
        whenNotPaused
        nonReentrant
        validScholarship(scholarshipId)
        onlyScholarshipCreatorOrAdmin(scholarshipId)
    {
        Scholarship storage scholarship = scholarships[scholarshipId];
        require(!scholarship.isCancelled, "Scholarship was cancelled");
        require(block.timestamp >= scholarship.endDate, "Scholarship not expired");
        require(scholarship.remainingGrants > 0, "No grants remaining");
        require(scholarship.active, "Scholarship already withdrawn or cancelled");

        uint256 refundAmount = scholarship.grantAmount * scholarship.remainingGrants;

        scholarship.active = false;
        scholarship.remainingGrants = 0;

        if (scholarship.tokenId == address(0)) {
            (bool success, ) = payable(scholarship.creator).call{value: refundAmount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 token = IERC20(scholarship.tokenId);
            SafeERC20.safeTransfer(token, scholarship.creator, refundAmount);
        }
        emit ScholarshipWithdrawn(scholarshipId, refundAmount);
    }

    function withdrawStuckTokens(address tokenAddress, uint256 amount)
        external
        onlyOwner
        whenNotPaused
    {
        require(tokenAddress != address(0), "Invalid token address");
        require(amount > 0, "Invalid amount");

        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        SafeERC20.safeTransfer(token, msg.sender, amount);
    }

    function withdrawStuckETH(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(address(this).balance >= amount, "Insufficient balance");

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // View functions
    function getScholarships() external view returns (Scholarship[] memory) {
        return scholarships;
    }

    function getApplicationsForScholarship(uint256 scholarshipId)
        external
        view
        validScholarship(scholarshipId)
        returns (Application[] memory)
    {
        uint256[] memory applicationIds = scholarshipApplications[scholarshipId];
        Application[] memory result = new Application[](applicationIds.length);

        for (uint256 i = 0; i < applicationIds.length; i++) {
            result[i] = applications[applicationIds[i]];
        }
        return result;
    }

    function getUserApplications(address user) external view returns (Application[] memory) {
        uint256[] memory applicationIds = userApplications[user];
        Application[] memory result = new Application[](applicationIds.length);

        for (uint256 i = 0; i < applicationIds.length; i++) {
            result[i] = applications[applicationIds[i]];
        }
        return result;
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getBalance() external view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    function getTokenBalance(address tokenId) external view onlyOwner returns (uint256) {
        require(checkIsContract(tokenId), "Invalid token address");
        IERC20 token = IERC20(tokenId);
        return token.balanceOf(address(this));
    }

    function getTokenIds() external view onlyOwner returns (address[] memory) {
        address[] memory tokenIds = new address[](scholarships.length);
        for (uint256 i = 0; i < scholarships.length; i++) {
            tokenIds[i] = scholarships[i].tokenId;
        }
        return tokenIds;
    }

    //private functions - helpers
    function checkIsContract(address target) private view returns (bool isContract) {
        if (target.code.length == 0) {
            isContract = false;
        } else {
            isContract = true;
        }
    }

    function EnsurePostScholarshipTokenTransfer(address tokenId, uint256 totalAmount) private {
        if (tokenId == address(0)) {
            // Process native ETH payment
            require(msg.value == totalAmount, "Native token: incorrect payment amount");
        } else {
            // Process ERC20 payment
            require(msg.value == 0, "ERC20 token: no ether required");
            require(checkIsContract(tokenId), "ERC20 token: invalid token address");
            IERC20 token = IERC20(tokenId);
            SafeERC20.safeTransferFrom(token, msg.sender, address(this), totalAmount);
        }
    }
}
