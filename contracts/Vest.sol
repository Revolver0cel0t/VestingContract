// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Token.sol";
import "hardhat/console.sol";

contract Vest {
    struct ClaimData {
        uint256 totalVestedAmount;
        uint256 dripped;
        uint256 claimStart;
        uint256 claimEnd;
        uint256 cliffEnd;
        bool claimInvalid;
    }

    address public claimToken;
    uint256 public totalClaimable;

    address private _owner;
    mapping(address => ClaimData) private _userClaims;
    mapping(address => uint256) public _claimableAmount;

    modifier onlyOwner() {
        require(
            _owner == msg.sender,
            "This function can only be called by the contract owner!"
        );
        _;
    }

    modifier onlyNonExpiredClaims(address claimee) {
        require(
            block.timestamp < _userClaims[claimee].claimEnd &&
                _remainingUserClaimableAmount(_userClaims[claimee]) > 0 &&
                _userClaims[claimee].claimStart > 0 &&
                !_userClaims[claimee].claimInvalid,
            "Expired or invalid claim"
        );
        _;
    }

    modifier onlyInactiveClaims(address claimee) {
        require(
            _userClaims[claimee].claimStart == 0 ||
                _userClaims[claimee].claimInvalid,
            "Claim already exists for this account"
        );
        _;
    }

    constructor(address owner, address token) {
        _owner = owner;
        claimToken = token;
    }

    function getUserClaimData(address claimee) public view returns (ClaimData memory) {
        return _userClaims[claimee];
    }

    function getUserClaimAmount(address claimee) public view returns (uint256) {
        return _claimableAmount[claimee];
    }

    function getOwner() public view returns (address) {
        return _owner;
    }

    function setOwner(address owner) public {
        _owner = owner;
    }

    function withdrawTokens(uint256 amount, address account) public onlyOwner {
        require(amount > 0, "Token amount has to be greater than 0!");
        RevToken tokenContract = RevToken(claimToken);
        require(
            tokenContract.balanceOf(address(this)) - amount >= totalClaimable,
            "Cant withdraw as it would lead to balances < claims"
        );
        tokenContract.transferFrom(address(this), account, amount);
    }

    function accrueRewardsForAccount(address claimee) public{
        ClaimData storage claimForUser = _userClaims[claimee];
        _accrueRewards(claimForUser, claimee);
    }

    function addClaimee(
        address claimee,
        uint256 amount,
        uint256 claimEndTimestamp,
        uint256 claimStartTimestamp,
        uint256 cliffPeriod
    ) public onlyOwner onlyInactiveClaims(claimee) {
        ClaimData storage claimForUser = _userClaims[claimee];
        _createChecks(amount, claimEndTimestamp, claimStartTimestamp);
        _setClaim(
            claimForUser,
            amount,
            claimEndTimestamp,
            claimStartTimestamp,
            cliffPeriod
        );
    }

    function restartClaim(
        address claimee,
        uint256 amount,
        uint256 claimEndTimestamp,
        uint256 claimStartTimestamp,
        uint256 cliffPeriod
    ) public onlyOwner {
        ClaimData storage claimForUser = _userClaims[claimee];
        _accrueRewards(claimForUser, claimee);
        _createChecks(amount, claimEndTimestamp, claimStartTimestamp);
        _clearClaimable(claimForUser);
        _setClaim(
            claimForUser,
            amount,
            claimEndTimestamp,
            claimStartTimestamp,
            cliffPeriod
        );
    }

    function removeClaimee(address claimee)
        public
        onlyOwner
        onlyNonExpiredClaims(claimee)
    {
        ClaimData storage claimForUser = _userClaims[claimee];
        _accrueRewards(claimForUser, claimee);
        _clearClaimable(claimForUser);
        claimForUser.claimInvalid = true;
    }

    function changeTotalVestedAmount(address claimee, uint256 newAmount)
        public
        onlyOwner
        onlyNonExpiredClaims(claimee)
    {
        ClaimData storage claimForUser = _userClaims[claimee];
        require(newAmount > 0, "New amount must be greater than 0!");
        require(
            claimForUser.dripped < newAmount,
            "That amount has already been vested to the user"
        );
        _accrueRewards(claimForUser, claimee);
        uint256 newTotal = totalClaimable +
            (newAmount) -
            (_remainingUserClaimableAmount(claimForUser));
        require(
            newTotal <= ERC20(claimToken).balanceOf(address(this)),
            "Cannot change claim amount as the total claims would exceed token reserves"
        );
        totalClaimable = newTotal;
        claimForUser.totalVestedAmount = newAmount;
    }

    function changeVestPeriod(address claimee, uint256 newPeriod)
        public
        onlyOwner
        onlyNonExpiredClaims(claimee)
    {
        ClaimData storage claimForUser = _userClaims[claimee];
        require(
            newPeriod > block.timestamp,
            "New claim period has to be greater than the current time"
        );
        if (claimForUser.cliffEnd > 0) {
            require(
                newPeriod > claimForUser.cliffEnd,
                "New claim period has to be greater than the cliff"
            );
        }
        _accrueRewards(claimForUser, claimee);
        claimForUser.claimEnd = newPeriod;
    }

    function changeCliff(address claimee, uint256 newCliff)
        public
        onlyOwner
        onlyNonExpiredClaims(claimee)
    {
        ClaimData storage claimForUser = _userClaims[claimee];
        require(claimForUser.cliffEnd != 0, "Can only modify if cliff exists");
        _cliffChecks(claimForUser, newCliff);
        claimForUser.cliffEnd = newCliff;
    }

    function withdrawAccruedTokens(address claimee) public {
        ClaimData storage claimForUser = _userClaims[claimee];
        _accrueRewards(claimForUser, claimee);
        require(_claimableAmount[claimee] > 0, "Nothing to claim");
        ERC20(claimToken).transferFrom(
            address(this),
            claimee,
            _claimableAmount[claimee]
        );
        _claimableAmount[claimee] = 0;
    }

    function _accrueRewards(ClaimData storage claimForUser, address claimee)
        internal
    {
        if (!claimForUser.claimInvalid) {
            uint256 rewards = _calculateUserClaimableRewards(
                claimForUser,
                block.timestamp
            );
            totalClaimable -= rewards;
            claimForUser.dripped += rewards;
            _claimableAmount[claimee] += rewards;
        }
    }

    function _calculateUserClaimableRewards(
        ClaimData memory claimForUser,
        uint256 currentTime
    ) internal pure returns (uint256) {
        if (
            (currentTime < claimForUser.cliffEnd) ||
            claimForUser.claimStart == 0
        ) {
            return 0;
        } else if (currentTime >= claimForUser.claimEnd) {
            return _remainingUserClaimableAmount(claimForUser);
        } else {
            uint256 timeFromStart = currentTime - claimForUser.claimStart;
            uint256 vestedAmount = (claimForUser.totalVestedAmount *
                timeFromStart) /
                (claimForUser.claimEnd - claimForUser.claimStart);
            vestedAmount = vestedAmount - claimForUser.dripped;
            return vestedAmount;
        }
    }

    function _cliffChecks(ClaimData memory _claim, uint256 newCliff)
        internal
        pure
    {
        require(_claim.cliffEnd < newCliff, "Cliff period cannot be reduced");
        require(
            _claim.claimEnd > newCliff,
            "Cliff cannot exceed end timestamp"
        );
        uint256 diff = (newCliff - _claim.claimStart) / 60 / 60 / 24;
        require(diff <= 180, "Cliff period cannot be greater than 6 months!");
    }

    function _createChecks(
        uint256 amount,
        uint256 claimEndTimestamp,
        uint256 claimStartTimestamp
    ) internal view {
        require(amount > 0, "Token amount has to be greater than 0!");
        require(
            claimEndTimestamp > block.timestamp,
            "End period must be greater than block timestamp"
        );
        require(
            claimEndTimestamp > claimStartTimestamp,
            "Start period must be lower than end period"
        );
        require(
            totalClaimable + amount <=
                ERC20(claimToken).balanceOf(address(this)),
            "Cannot add a user as the total claims would exceed token reserves"
        );
    }

    function _setClaim(
        ClaimData storage _claim,
        uint256 amount,
        uint256 claimEndTimestamp,
        uint256 claimStartTimestamp,
        uint256 cliffPeriod
    ) internal {
        totalClaimable += amount;
        _claim.claimEnd = claimEndTimestamp;
        _claim.totalVestedAmount = amount;
        _claim.claimStart = claimStartTimestamp;
        _claim.dripped = 0;
        _claim.claimInvalid = false;
        if (cliffPeriod > 0) {
            _cliffChecks(_claim, cliffPeriod);
            _claim.cliffEnd = cliffPeriod;
        }
    }

    function _clearClaimable(ClaimData memory _claim) internal {
        totalClaimable -= (_claim.totalVestedAmount - _claim.dripped);
    }

    function _remainingUserClaimableAmount(ClaimData memory _claim)
        internal
        pure
        returns (uint256)
    {
        return _claim.totalVestedAmount - _claim.dripped;
    }
}
