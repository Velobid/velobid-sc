// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.29;

contract Auction {
    // ===== Constants =====
    address public owner;
    uint256 public userCount;
    uint256 public auctionCount;
    DataStruct public data;

    // ===== Structs =====
    struct UserStruct {
        uint256 point;
        uint256 winrate;
        uint256 totalBid;
        uint256 totalValueBid;
        uint256 totalAuctionCreated;
        uint256 totalAuctionParticipated;
        uint256 totalWinningBids;
        uint256 averageBidValue;
        bool registered;
    }
    
    struct AuctionStruct {
        uint256 auctionId;
        address beneficiary;
        string auctionName;
        string auctionDescription;
        uint256 auctionEndTime;
        uint256 biddingTime;
        uint256 additionalTime;
        uint256 startingBid;
        uint256 highestBid;
        address highestBidder;
        uint256 totalVolumeBid;
        address winner;
        mapping(address => uint256) pendingReturn;
        bool ended;
    }
    
    struct DataStruct {
        uint256 totalAuction;
        uint256 totalActiveAuction;
        uint256 totalBidders;
        uint256 totalBid;
        uint256 totalVolumeBid;
        uint256 highestBid;
        address highestBidder;
        uint256 averageBidValue;
        uint256 totalUsers;
    }

    // ===== Mappings =====
    mapping(address => UserStruct) public users;
    mapping(uint256 => AuctionStruct) public auctions;
    mapping(address => uint256[]) public userAuctions;
    mapping(uint => address) public userIndex;
    mapping(uint => uint256) public auctionIndex;
    mapping(address => uint256) public topBidders;
    mapping(address => uint256) public topSpenders;

    // ===== Events =====
    event UserRegistered(address indexed user);
    event UserUpdated(address indexed user);
    event AuctionCreated(uint indexed auctionId, string auctionName);
    event HighestBidIncreased(address indexed bidder, uint amount);
    event AuctionEnded(address indexed winner, uint amount);
    event WithdrawFailed(address indexed user, uint amount);
    event WithdrawSuccess(address indexed user, uint amount);
    event EndFailed(uint indexed auctionId);
    event EndSuccess(uint indexed auctionId);
    event OwnerTransferred(address indexed previous, address indexed current);
    event BidTimeIncreased(uint indexed id, uint time);

    // ===== Constructor =====
    constructor() {
        owner = msg.sender;
    }

    // ===== Modifiers =====
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }
    
    bool private reentrant = false;
    modifier nonReentrant() {
        require(!reentrant, "ReentrancyGuard: reentrant call");
        reentrant = true;
        _;
        reentrant = false;
    }
    
    modifier mustRegister() {
        require(users[msg.sender].registered, "User must connect wallet first");
        _;
    }

    // ===== Handle User =====
    // Register User - Check wallet connection
    function registerUser() external {
        require(!users[msg.sender].registered, "Wallet already registered");
        UserStruct storage newUser = users[msg.sender];
        newUser.registered = true;
        userIndex[userCount] = msg.sender;
        data.totalUsers++;
        userCount++;
        emit UserRegistered(msg.sender);
    }
    
    // Get Users
    function getUsers(uint _startIndex, uint _limit) external view returns (address[] memory) {
        require(userCount > 0, "No user found");
        require(_startIndex < userCount, "Start index out of bounds");
        
        uint endIndex = _startIndex + _limit;
        if (endIndex > userCount) {
            endIndex = userCount;
        }
        
        address[] memory newUsers = new address[](endIndex - _startIndex);
        for (uint i = _startIndex; i < endIndex; i++) {
            newUsers[i - _startIndex] = userIndex[i];
        }
        return newUsers;
    }

    // ===== Handle Auction =====
    // Create Auction
    function createAuction(string memory _auctionName, string memory _auctionDescription, uint256 _biddingTime, uint256 _startingBid) external mustRegister {
        require(_biddingTime > 0, "Auction must be bidding for more than 0 seconds");
        uint256 auctionId = auctionCount;
        AuctionStruct storage newAuction = auctions[auctionId];

        newAuction.auctionId = auctionId;
        newAuction.beneficiary = msg.sender;
        newAuction.auctionName = _auctionName;
        newAuction.auctionDescription = _auctionDescription;
        newAuction.auctionEndTime = block.timestamp + _biddingTime;
        newAuction.biddingTime = _biddingTime;
        newAuction.startingBid = _startingBid;
        newAuction.ended = false;

        userAuctions[msg.sender].push(auctionId);
        auctionIndex[auctionCount] = auctionId;
        auctionCount++;
        data.totalAuction++;
        
        users[msg.sender].totalAuctionCreated++;
        
        emit AuctionCreated(auctionId, _auctionName);
    }
    
    // Rest of the contract remains the same...
    // [Previous implementations of getUserAuctions, getAuctions, bid, withdraw, auctionEnd, transferOwnership]
    // ... (keep all other functions exactly as they were)
    
    function getUserAuctions(address _user) external view returns (uint256[] memory) {
        return userAuctions[_user];
    }

    function getAuctions(uint _startIndex, uint _limit) external view returns (uint256[] memory) {
        require(_startIndex < auctionCount, "Start index out of bounds");
        
        uint endIndex = _startIndex + _limit;
        if (endIndex > auctionCount) {
            endIndex = auctionCount;
        }
        
        uint256[] memory newAuction = new uint256[](endIndex - _startIndex);
        for (uint i = _startIndex; i < endIndex; i++) {
            newAuction[i - _startIndex] = auctionIndex[i];
        }
        return newAuction;
    }

    function bid(uint256 _auctionId, uint256 _amount) external payable nonReentrant mustRegister returns (bool) {
        require(_auctionId < auctionCount, "Invalid Auction Id");
        AuctionStruct storage auction = auctions[_auctionId];

        require(_amount >= auction.startingBid, "Bid must be >= starting bid");
        require(_amount > auction.highestBid, "Bid must be > highest bid");
        require(!auction.ended && block.timestamp <= auction.auctionEndTime, "Auction has ended");

        // Extend bidding time if less than 10 minutes left
        if (auction.auctionEndTime - block.timestamp < 600) {
            auction.auctionEndTime = block.timestamp + 300;
            auction.additionalTime += 300;
            emit BidTimeIncreased(_auctionId, 300);
        }

        // Refund previous highest bidder
        if (auction.highestBidder != address(0)) {
            auction.pendingReturn[auction.highestBidder] += auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = _amount;
        auction.totalVolumeBid += _amount;

        // Update user stats
        UserStruct storage user = users[msg.sender];
        user.point += 10;
        user.totalBid++;
        user.totalValueBid += _amount;
        if (user.totalBid > 0) {
            user.averageBidValue = user.totalValueBid / user.totalBid;
        }
        user.totalAuctionParticipated++;

        // Update global stats
        if (_amount > data.highestBid) {
            data.highestBid = _amount;
            data.highestBidder = msg.sender;
        }

        data.totalBid++;
        data.totalVolumeBid += _amount;
        if (data.totalBid > 0) {
            data.averageBidValue = data.totalVolumeBid / data.totalBid;
        } 

        // Update top rankings
        updateTopBiddersAndSpenders(msg.sender);

        emit HighestBidIncreased(msg.sender, _amount);
        return true;
    }



    function withdraw(uint256 _auctionId) external mustRegister nonReentrant returns (bool){
        require(_auctionId < auctionCount, "Invalid Auction Id");

        AuctionStruct storage newAuction = auctions[_auctionId];
        uint256 amount = newAuction.pendingReturn[msg.sender];
        require(amount > 0, "No funds to withdraw");
        newAuction.pendingReturn[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        
        if (!success) {
            newAuction.pendingReturn[msg.sender] = amount;
            emit WithdrawFailed(msg.sender, amount);
            return false;
        }

        emit WithdrawSuccess(msg.sender, amount);
        return true;
    }


    function updateTopBiddersAndSpenders(address userAddress) internal {
        uint256 currentTotal = users[userAddress].totalValueBid;
        uint256 senderSpend = topSpenders[msg.sender];
        uint256 senderBids = topBidders[msg.sender];
        uint256 userBids = topBidders[userAddress];
        
        // Update top spenders
        if (senderSpend < currentTotal) {
            delete topSpenders[msg.sender];
            delete topBidders[msg.sender];
            
            data.totalUsers--;
            
            topBidders[msg.sender] = senderBids + 1;
            topSpenders[msg.sender] = currentTotal;
            users[userAddress].totalAuctionParticipated++;
        } 
        // Update total spendings
        else if (senderSpend > currentTotal) {
            delete topSpenders[userAddress];
            delete topBidders[userAddress];
            
            data.totalUsers--;
            
            topBidders[userAddress] = userBids + 1;
            topSpenders[userAddress] = users[userAddress].totalValueBid;
        } 
        // Update total biddings
        else if (senderBids < currentTotal) {
            delete topSpenders[msg.sender];
            delete topBidders[msg.sender];
            
            data.totalUsers--;
            
            topSpenders[msg.sender] = senderSpend + 1;
            topBidders[userAddress] = users[userAddress].totalValueBid;
        } 
        // Update total biddings and spendings
        else if (senderBids > currentTotal) {
            delete topSpenders[msg.sender];
            delete topBidders[msg.sender];
            
            data.totalUsers--;
            
            topSpenders[msg.sender] = senderSpend + 1;
            topBidders[userAddress] = users[userAddress].totalValueBid;
        }
        // No action needed
        else {
            return;
        }
    }

    function auctionEnd(uint256 _auctionId) external mustRegister nonReentrant returns (bool){
        require(_auctionId < auctionCount, "Invalid Auction Id");

        AuctionStruct storage newAuction = auctions[_auctionId];
        UserStruct storage newUser = users[msg.sender];
        require(newAuction.ended == false && block.timestamp >= newAuction.auctionEndTime, "Auction not ended yet");

        newAuction.ended = true;
        newAuction.winner = newAuction.highestBidder;
        newUser.totalWinningBids++;
        newUser.winrate = newUser.totalAuctionParticipated / newUser.totalWinningBids;

        uint256 amount = newAuction.highestBid;
        newAuction.highestBid = 0;

        (bool success, ) = payable(newAuction.beneficiary).call{value: amount}("");
        
        if (!success) {
            newAuction.highestBid = amount;
            emit EndFailed(_auctionId);
            return false;
        }

        emit EndSuccess(_auctionId);
        return true;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        emit OwnerTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}