// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RebaseIDO is Ownable {
  
    using SafeMath for uint256;

    IERC20 public rebaseToken;
    address payable public recipientAddress;
    uint256 public minContribution;
    uint256 public maxContribution;
    uint256 public hardCap;
    uint256 public rate;

    // Time settings
    uint256 public startTime;
    uint256 public endTime;
    uint256 public claimTime;

    // For tracking purposes
    uint256 public totalBnbRaised;
    uint256 public totalParticipants;
    uint256 public totalClaimedParticipants;
    uint256 public totalPendingClaimToken;
    

    bool public whitelistEnabled = true;

    //Store the information of all users
    struct Account {
        uint256 contribution;           // user's contributed BNB amount
        uint256 tokenAllocation;        // user's token allocation 
        uint256 claimedTimestamp;       // user's last claimed timestamp. 0 means never claim
    }

    mapping(address => Account) public accounts;
    mapping(address => bool) public whiteLists;
    mapping(address => uint256) public claimCounts;

    constructor(address _token) {
        rebaseToken = IERC20(_token);
        recipientAddress = payable(msg.sender);
    }

    function contribute() public payable {
        require(block.timestamp >= startTime, "IDO not started yet");
        require(block.timestamp <= endTime, "IDO ended");
        if(whitelistEnabled)
            require(whiteLists[_msgSender()], "You are not in whitelist");

        Account storage userAccount = accounts[_msgSender()];
        uint256 _contribution = msg.value;
        uint256 _totalContribution = userAccount.contribution.add(_contribution);

        require(_totalContribution >= minContribution, "Contribution is lower than minimum contribution threshold");
        require(_totalContribution <= maxContribution, "Contribution exceeded maximum contribution threshold");
        require(totalBnbRaised.add(_contribution) <= hardCap, "Exceeded hardcap");
        
        // Forward funds
        forwardFunds(_contribution);

        // Calculate entitled token amount
        uint256 _tokenAllocation = calculateTokenAllocation(_contribution);

        // Set tracking variables
        if (userAccount.contribution == 0) 
            totalParticipants = totalParticipants.add(1);

        totalBnbRaised = totalBnbRaised.add(_contribution);
        totalPendingClaimToken = totalPendingClaimToken.add(_tokenAllocation);

        // Set user contribution details
        userAccount.contribution = userAccount.contribution.add(_contribution);
        userAccount.tokenAllocation = userAccount.tokenAllocation.add(_tokenAllocation);

        emit Contributed(_msgSender(), _contribution);
    }

    function claim() external {
        Account storage userAccount = accounts[_msgSender()];
        uint256 _tokenAllocation = userAccount.tokenAllocation;

        require(block.timestamp >= claimTime, "Can not claim at this time");
        require(_tokenAllocation > 0, "Nothing to claim");
        
        //Validate whether contract token balance is sufficient
        uint256 contractTokenBalance = rebaseToken.balanceOf(address(this));
        require(contractTokenBalance >= _tokenAllocation, "Insufficient token in contract");

        //Update user details
        userAccount.claimedTimestamp = block.timestamp;
        userAccount.tokenAllocation = 0;

        //For tracking
        totalPendingClaimToken = totalPendingClaimToken.sub(_tokenAllocation);
        totalClaimedParticipants = totalClaimedParticipants.add(1);

        //Release token
        rebaseToken.transfer(_msgSender(), _tokenAllocation);

        emit Claimed(_msgSender(), _tokenAllocation);
    }

    function calculateTokenAllocation(uint256 _amount) internal view returns (uint256){
        return _amount.mul(rate).div(1 *10**18);
    }

    function setRecipientAddress(address _recipientAddress) external onlyOwner {
        require(_recipientAddress != address(0), "Zero address");
        recipientAddress = payable(_recipientAddress);
    }

    function setTime(uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(_startTime < _endTime, "Start time should be less than end time");
        startTime = _startTime;
        endTime = _endTime;
    }

    function setClaimTime(uint256 _claimTime) external onlyOwner {
        claimTime = _claimTime;
    }

    function setRebaseToken(address _token) external onlyOwner {
        require(_token != address(0), "Zero address");
        rebaseToken = IERC20(_token);
    }

    function setContribution(uint256 _minContribution, uint256 _maxContribution) external onlyOwner {
        minContribution = _minContribution;
        maxContribution = _maxContribution;
    }

    function setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function setHardCap(uint256 _hardCap) external onlyOwner {
        hardCap = _hardCap;
    }

    function setWhitelistEnabled(bool _bool) external onlyOwner {
        whitelistEnabled = _bool;
    }

    function addToWhiteList(address[] memory _accounts) external onlyOwner {
        require(_accounts.length > 0, "Invalid input");
        for (uint256 index = 0; index < _accounts.length; index++) {
            whiteLists[_accounts[index]] = true;
        }
    }

    function removeFromWhiteList(address[] memory _accounts) external onlyOwner {
        require(_accounts.length > 0, "Invalid input");
        for (uint256 index = 0; index < _accounts.length; index++) {
            whiteLists[_accounts[index]] = false;
        }
    }

    function forwardFunds(uint256 _contribution) internal {
        recipientAddress.transfer(_contribution);
    }

    function rescueToken(address _token, address _to) public onlyOwner returns (bool _sent) {
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        _sent = IERC20(_token).transfer(_to, _contractBalance);
    }

    function clearStuckBalance() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    receive() external payable {}

    event Contributed(address account, uint256 contribution);
    event Claimed(address account, uint256 tokenQuantity);
}
