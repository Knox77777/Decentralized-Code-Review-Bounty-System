// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract CodeReviewBounty {
    
    struct Review {
        uint256 reviewId;
        address reviewer;
        string reviewContent;
        uint256 timestamp;
        uint256 votes;
        bool isActive;
    }
    
    struct Bounty {
        uint256 bountyId;
        address creator;
        string codeDescription;
        string repositoryLink;
        uint256 bountyAmount;
        uint256 deadline;
        bool isActive;
        bool isPaid;
        address winningReviewer;
        uint256 totalReviews;
    }
    
    // State variables
    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(uint256 => Review)) public reviews; // bountyId => reviewId => Review
    mapping(uint256 => mapping(address => bool)) public hasReviewed; // bountyId => reviewer => bool
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasVoted; // bountyId => reviewId => voter => bool
    
    uint256 public nextBountyId = 1;
    uint256 public platformFeePercent = 5; // 5% platform fee
    address public owner;
    
    // Events
    event BountyCreated(uint256 indexed bountyId, address indexed creator, uint256 bountyAmount, uint256 deadline);
    event ReviewSubmitted(uint256 indexed bountyId, uint256 indexed reviewId, address indexed reviewer);
    event VoteCast(uint256 indexed bountyId, uint256 indexed reviewId, address indexed voter);
    event BountyPaid(uint256 indexed bountyId, address indexed winner, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier validBounty(uint256 _bountyId) {
        require(_bountyId > 0 && _bountyId < nextBountyId, "Invalid bounty ID");
        require(bounties[_bountyId].isActive, "Bounty is not active");
        _;
    }
    
    modifier beforeDeadline(uint256 _bountyId) {
        require(block.timestamp < bounties[_bountyId].deadline, "Bounty deadline has passed");
        _;
    }
    
    modifier afterDeadline(uint256 _bountyId) {
        require(block.timestamp >= bounties[_bountyId].deadline, "Bounty deadline has not passed yet");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Create a new code review bounty
     * @param _codeDescription Description of the code to be reviewed
     * @param _repositoryLink Link to the code repository
     * @param _reviewPeriodDays Number of days for the review period
     */
    function createBounty(
        string memory _codeDescription,
        string memory _repositoryLink,
        uint256 _reviewPeriodDays
    ) external payable {
        require(msg.value > 0, "Bounty amount must be greater than 0");
        require(_reviewPeriodDays > 0 && _reviewPeriodDays <= 30, "Review period must be between 1-30 days");
        require(bytes(_codeDescription).length > 0, "Code description cannot be empty");
        require(bytes(_repositoryLink).length > 0, "Repository link cannot be empty");
        
        uint256 deadline = block.timestamp + (_reviewPeriodDays * 1 days);
        
        bounties[nextBountyId] = Bounty({
            bountyId: nextBountyId,
            creator: msg.sender,
            codeDescription: _codeDescription,
            repositoryLink: _repositoryLink,
            bountyAmount: msg.value,
            deadline: deadline,
            isActive: true,
            isPaid: false,
            winningReviewer: address(0),
            totalReviews: 0
        });
        
        emit BountyCreated(nextBountyId, msg.sender, msg.value, deadline);
        nextBountyId++;
    }
    
    /**
     * @dev Submit a code review for a bounty
     * @param _bountyId ID of the bounty to review
     * @param _reviewContent Content of the code review
     */
    function submitReview(
        uint256 _bountyId,
        string memory _reviewContent
    ) external validBounty(_bountyId) beforeDeadline(_bountyId) {
        require(!hasReviewed[_bountyId][msg.sender], "You have already reviewed this bounty");
        require(msg.sender != bounties[_bountyId].creator, "Bounty creator cannot review their own code");
        require(bytes(_reviewContent).length > 0, "Review content cannot be empty");
        
        uint256 reviewId = bounties[_bountyId].totalReviews;
        
        reviews[_bountyId][reviewId] = Review({
            reviewId: reviewId,
            reviewer: msg.sender,
            reviewContent: _reviewContent,
            timestamp: block.timestamp,
            votes: 0,
            isActive: true
        });
        
        hasReviewed[_bountyId][msg.sender] = true;
        bounties[_bountyId].totalReviews++;
        
        emit ReviewSubmitted(_bountyId, reviewId, msg.sender);
    }
    
    /**
     * @dev Vote for the best review (community voting)
     * @param _bountyId ID of the bounty
     * @param _reviewId ID of the review to vote for
     */
    function voteForReview(
        uint256 _bountyId,
        uint256 _reviewId
    ) external validBounty(_bountyId) afterDeadline(_bountyId) {
        require(_reviewId < bounties[_bountyId].totalReviews, "Invalid review ID");
        require(!hasVoted[_bountyId][_reviewId][msg.sender], "You have already voted for this review");
        require(reviews[_bountyId][_reviewId].isActive, "Review is not active");
        require(!bounties[_bountyId].isPaid, "Bounty has already been paid");
        
        // Allow 7 days after deadline for voting
        require(block.timestamp <= bounties[_bountyId].deadline + 7 days, "Voting period has ended");
        
        reviews[_bountyId][_reviewId].votes++;
        hasVoted[_bountyId][_reviewId][msg.sender] = true;
        
        emit VoteCast(_bountyId, _reviewId, msg.sender);
    }
    
    /**
     * @dev Finalize bounty and pay the winner (can be called by anyone after voting period)
     * @param _bountyId ID of the bounty to finalize
     */
    function finalizeBounty(uint256 _bountyId) external validBounty(_bountyId) {
        require(!bounties[_bountyId].isPaid, "Bounty has already been paid");
        require(block.timestamp > bounties[_bountyId].deadline + 7 days, "Voting period has not ended");
        
        // Find the review with the most votes
        uint256 winningReviewId = 0;
        uint256 maxVotes = 0;
        
        for (uint256 i = 0; i < bounties[_bountyId].totalReviews; i++) {
            if (reviews[_bountyId][i].votes > maxVotes) {
                maxVotes = reviews[_bountyId][i].votes;
                winningReviewId = i;
            }
        }
        
        // If no reviews were submitted, return funds to creator
        if (bounties[_bountyId].totalReviews == 0) {
            payable(bounties[_bountyId].creator).transfer(bounties[_bountyId].bountyAmount);
        } else {
            // Pay the winning reviewer
            address winner = reviews[_bountyId][winningReviewId].reviewer;
            uint256 platformFee = (bounties[_bountyId].bountyAmount * platformFeePercent) / 100;
            uint256 winnerAmount = bounties[_bountyId].bountyAmount - platformFee;
            
            bounties[_bountyId].winningReviewer = winner;
            bounties[_bountyId].isPaid = true;
            bounties[_bountyId].isActive = false;
            
            // Transfer payments
            payable(winner).transfer(winnerAmount);
            payable(owner).transfer(platformFee);
            
            emit BountyPaid(_bountyId, winner, winnerAmount);
        }
    }
    
    // View functions
    function getBounty(uint256 _bountyId) external view returns (Bounty memory) {
        return bounties[_bountyId];
    }
    
    function getReview(uint256 _bountyId, uint256 _reviewId) external view returns (Review memory) {
        return reviews[_bountyId][_reviewId];
    }
    
    function getActiveBountiesCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i < nextBountyId; i++) {
            if (bounties[i].isActive) count++;
        }
        return count;
    }
    
    // Owner functions
    function updatePlatformFee(uint256 _newFeePercent) external onlyOwner {
        require(_newFeePercent <= 10, "Platform fee cannot exceed 10%");
        platformFeePercent = _newFeePercent;
    }
    
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}
