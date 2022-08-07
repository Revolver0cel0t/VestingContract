// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Vest {
    struct ClaimData {
        uint256 totalVestedAmount;
        uint256 claimable;
        uint256 dripped;
        uint256 claimStart;
        uint256 claimEnd;
        uint256 cliffEnd;
    }

    address private _owner;
    address public claimToken;
    uint256 public totalClaimable;

    mapping(address => ClaimData) private userClaims;

    modifier onlyOwner() {
        require(
            _owner == msg.sender,
            "This function can only be called by the contract owner!"
        );
        _;
    }

    modifier onlyExistingClaims(address claimee) {
        require(
            userClaims[claimee].claimStart > 0,
            "Claim doesnt exist on account"
        );
        _;
    }

    modifier onlyActiveClaims(address claimee) {
        require(
            block.timestamp < userClaims[claimee].claimEnd &&
                userClaims[claimee].dripped -
                    userClaims[claimee].totalVestedAmount <
                0 &&
                userClaims[claimee].claimStart > 0,
            "Expired claim"
        );
        _;
    }

    modifier onlyExpiredClaims(address claimee) {
        require(
            userClaims[claimee].claimStart > 0 &&
                !(block.timestamp < userClaims[claimee].claimEnd &&
                    userClaims[claimee].dripped -
                        userClaims[claimee].totalVestedAmount <
                    0),
            "Active claim"
        );
        _;
    }

    modifier onlyInactiveClaims(address claimee) {
        require(
            userClaims[claimee].claimStart == 0,
            "Claim already exists for this account"
        );
        _;
    }

    constructor(address owner, address token) {
        _owner = owner;
        claimToken = token;
    }

    function depositToken(uint256 amount) public {
        require(amount > 0, "Token amount has to be greater than 0!");
        ERC20(claimToken).transferFrom(msg.sender, address(this), amount);
    }

    function withdrawTokens(uint256 amount, address account) public onlyOwner {
        require(amount > 0, "Token amount has to be greater than 0!");
        ERC20 tokenContract = ERC20(claimToken);
        require(
            tokenContract.balanceOf(address(this)) - amount >= totalClaimable,
            "Cant withdraw as it would lead to balances < claims"
        );
        tokenContract.transferFrom(address(this), account, amount);
    }

    function addClaimee(
        address claimee,
        uint256 amount,
        uint256 claimEndTimestamp,
        uint256 claimStartTimestamp,
        uint256 cliffPeriod
    ) public onlyOwner onlyInactiveClaims(claimee) {
        ClaimData storage claimForUser = userClaims[claimee];
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
    ) public onlyOwner onlyExpiredClaims(claimee) {
        ClaimData storage claimForUser = userClaims[claimee];
        require(
            claimForUser.totalVestedAmount - claimForUser.dripped == 0,
            "Cannot create a new claim unless the old one has its claims withdrawn by the user"
        );
        _createChecks(amount, claimEndTimestamp, claimStartTimestamp);
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
        onlyExistingClaims(claimee)
    {
        ClaimData storage claimForUser = userClaims[claimee];
        _accrueRewards(claimForUser);
        _clearClaim(claimForUser);
    }

    function changeTotalVestedAmount(address claimee, uint256 newAmount)
        public
        onlyOwner
        onlyActiveClaims(claimee)
    {
        ClaimData storage claimForUser = userClaims[claimee];
        require(newAmount > 0, "New amount must be greater than 0!");
        require(
            claimForUser.dripped < newAmount,
            "That amount has already been vested to the user"
        );
        uint256 newTotal = totalClaimable +
            (newAmount) -
            (claimForUser.totalVestedAmount - claimForUser.dripped);
        require(
            newTotal <= ERC20(claimToken).balanceOf(address(this)),
            "Cannot change claim amount as the total claims would exceed token reserves"
        );
        _accrueRewards(claimForUser);
        totalClaimable = newTotal;
        claimForUser.totalVestedAmount = newAmount;
    }

    function changeVestPeriod(address claimee, uint256 newPeriod)
        public
        onlyOwner
        onlyActiveClaims(claimee)
    {
        ClaimData storage claimForUser = userClaims[claimee];
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
        _accrueRewards(claimForUser);
        claimForUser.claimEnd = newPeriod;
    }

    function changeCliff(address claimee, uint256 newCliff)
        public
        onlyOwner
        onlyActiveClaims(claimee)
    {
        ClaimData storage claimForUser = userClaims[claimee];
        require(claimForUser.cliffEnd != 0, "Can only modify if cliff exists");
        _cliffChecks(claimForUser, newCliff);
        claimForUser.cliffEnd = newCliff;
    }

    function withdrawAccruedTokens(address claimee) public {
        ClaimData storage claimForUser = userClaims[claimee];
        _accrueRewards(claimForUser);
        require(claimForUser.claimable > 0, "Nothing to claim");
        ERC20(claimToken).transferFrom(
            address(this),
            claimee,
            claimForUser.claimable
        );
        claimForUser.claimable = 0;
    }

    function _accrueRewards(ClaimData storage claimForUser) internal {
        uint256 rewards = _calculateUserClaimableRewards(
            claimForUser,
            block.timestamp
        );
        totalClaimable -= rewards;
        claimForUser.dripped += rewards;
        claimForUser.claimable += rewards;
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
            return claimForUser.totalVestedAmount - (claimForUser.dripped);
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
        ClaimData memory _claim,
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
        if (cliffPeriod > 0) {
            _cliffChecks(_claim, cliffPeriod);
            _claim.cliffEnd = cliffPeriod;
        }
    }

    function _clearClaim(ClaimData memory _claim) internal {
        totalClaimable -= (_claim.totalVestedAmount - _claim.dripped);
        _claim.claimEnd = 0;
        _claim.cliffEnd = 0;
        _claim.claimStart = 0;
        _claim.totalVestedAmount = 0;
        _claim.claimable = 0;
        _claim.dripped = 0;
    }
}
