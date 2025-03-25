// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

contract Auction {
    // ===== Constants =====
    address public owner;
    uint256 public userCount;
    uint256 public auctionCount;
    DataStruct public data;

    // ===== Structs =====
    struct UserStruct {
        string username;
        uint256 point;
        uint256 winrate;
        uint256 totalBid;
        uint256 totalValueBid;
        uint256 totalAuctionCreated;
        uint256 totalAuctionParticipated;
        uint256 totalWinningBids;
        uint256 averageBidValue;
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
    mapping(string => bool) public usernames;
    mapping(uint256 => AuctionStruct) public auctions;
    mapping(address => uint256[]) public userAuctions;
    mapping(uint => address) public userIndex;
    mapping(uint => uint256) public auctionIndex;
    mapping(address => uint256) public topBidders;
    mapping(address => uint256) public topSpenders;

    // ===== Events =====
    event UserRegistered(address indexed user, string username);
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
    // onlyOwner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }
    // nonReentrant
    bool private reentrant = false;
    modifier nonReentrant() {
        require(!reentrant, "ReentrancyGuard: reentrant call");
        reentrant = true;
        _;
        reentrant = false;
    }
    // mustRegister
    modifier mustRegister() {
        require(bytes(users[msg.sender].username).length != 0, "User must register first");
        _;
    }

    // ===== Handle User =====
    // Register User
    function registerUser(string memory _username) external {
        require(bytes(users[msg.sender].username).length == 0, "You already registered");
        require(!usernames[_username], "Username already taken, please try with a different username");
        require(bytes(_username).length >= 5 && bytes(_username).length <= 15, "Username must be 5-15 characters");
        UserStruct storage newUser = users[msg.sender];
        newUser.username = _username;
        userIndex[userCount] = msg.sender;
        usernames[_username] = true;
        data.totalUsers++;
        userCount++;
        emit UserRegistered(msg.sender, _username);
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
        
        emit AuctionCreated(auctionId, _auctionName);
    }
    // Get User Auctions
    function getUserAuctions(address _user) external view returns (uint256[] memory) {
        return userAuctions[_user];
    }
    // Get Auctions
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
    // Bid
    function bid(uint256 _auctionId, uint256 _amount) external nonReentrant mustRegister returns (bool){
        require(_auctionId < auctionCount, "Invalid Auction Id");
        require(_amount >= auctions[_auctionId].startingBid, "Bid cannot be less than starting bid");
        require(_amount > auctions[_auctionId].highestBid, "Bid cannot be less than highest bid");
        require(auctions[_auctionId].ended == false && block.timestamp <= auctions[_auctionId].auctionEndTime, "Auction has ended");
        
        AuctionStruct storage newAuction = auctions[_auctionId];
        UserStruct storage newUser = users[msg.sender];
        if(newAuction.auctionEndTime - block.timestamp < 600) {
            newAuction.auctionEndTime = block.timestamp + 300;
            newAuction.additionalTime += block.timestamp + 300;
            emit BidTimeIncreased(_auctionId, _amount);
        }

        address highestBidder = newAuction.highestBidder;
        uint256 highestBid = newAuction.highestBid;
        newAuction.pendingReturn[highestBidder] += highestBid;
        newAuction.highestBidder = msg.sender;
        newAuction.highestBid = _amount;
        newAuction.totalVolumeBid += _amount;
        
        newUser.point += 10;
        newUser.totalBid++;
        newUser.totalValueBid += _amount;
        newUser.averageBidValue = newUser.totalValueBid / newUser.totalBid;
        newUser.totalAuctionParticipated++;

        if(_amount > data.totalVolumeBid) {
            data.highestBidder = msg.sender;
            data.highestBid = _amount;
        }
        data.totalBid++;
        data.totalVolumeBid += _amount;
        data.averageBidValue = data.totalVolumeBid / data.totalBid;

        topBidders[msg.sender]++;
        topSpenders[msg.sender] += _amount;

        return true;
    }
    // Withdraw
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
    // Auction End
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

    // ===== Handle Ownership =====
    function transferOwnership(address _newOwner) external onlyOwner {
        emit OwnerTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}