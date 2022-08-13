// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Token.sol";
import "./IVest.sol";
import "./Structs.sol";
import "./Helpers.sol";

contract Vest {
    address public claimToken;
    uint256 public totalClaimable;

    address private _owner;
    mapping(address => ClaimData) private _userClaims;
    mapping(address => uint256) public _claimableAmount;

    modifier onlyOwner() {
        if(
            _owner != msg.sender
        ){
            revert IVest.OnlyOwner();
        }
        _;
    }

    modifier onlyNonExpiredClaims(address claimee) {
        ClaimData memory userClaim = _userClaims[claimee];
        if(!(block.timestamp < userClaim.claimEnd &&
                _remainingUserClaimableAmount(userClaim) > 0 &&
                userClaim.claimStart > 0 &&
                !userClaim.claimInvalid)){
                    revert IVest.OnlyNonExpiredClaims();
        }
        _;
    }

    constructor(address owner, address token) {
        _owner = owner;
        claimToken = token;
    }

    function getUserClaimData(address claimee)
        public
        view
        returns (ClaimData memory)
    {
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
        if(amount<=0){
            revert IVest.TokenAmountZero();
        }
        RevToken tokenContract = RevToken(claimToken);
        if(!(tokenContract.balanceOf(address(this)) - amount >= totalClaimable)){
            revert IVest.BalancesLowerThanClaims();
        }
        tokenContract.transferFrom(address(this), account, amount);
    }

    function accrueRewardsForAccount(address claimee) public {
        ClaimData storage claimForUser = _userClaims[claimee];
        _accrueRewards(claimForUser, claimee);
    }

    function addClaimee(
        address claimee,
        uint256 amount,
        uint256 claimEndTimestamp,
        uint256 claimStartTimestamp,
        uint256 cliffPeriod
    ) public onlyOwner {
        ClaimData storage claimForUser = _userClaims[claimee];
        if(!(claimForUser.claimStart == 0 || claimForUser.claimInvalid)){
            revert IVest.ClaimAlreadyExists();
        }
        _createChecks(amount, claimEndTimestamp, claimStartTimestamp,totalClaimable,claimToken,address(this));
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
        _createChecks(amount, claimEndTimestamp, claimStartTimestamp,totalClaimable,claimToken,address(this));
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
        if(newAmount <=0){
            revert IVest.TokenAmountZero();
        }
        if(claimForUser.dripped >= newAmount){
            revert IVest.AmountAlreadyDripped();
        }
        _accrueRewards(claimForUser, claimee);
        uint256 newTotal = totalClaimable +
            (newAmount) -
            (_remainingUserClaimableAmount(claimForUser));
        if(!(newTotal <= ERC20(claimToken).balanceOf(address(this)))){
            revert IVest.ClaimAdditionExceedsReserves();
        }
        totalClaimable = newTotal;
        claimForUser.totalVestedAmount = newAmount;
    }

    function changeVestPeriod(address claimee, uint256 newPeriod)
        public
        onlyOwner
        onlyNonExpiredClaims(claimee)
    {
        ClaimData storage claimForUser = _userClaims[claimee];
        if(!(newPeriod > block.timestamp)){
            revert IVest.NewPeriodSmallerThanClaim();
        }
        if (claimForUser.cliffEnd > 0 && !(newPeriod > claimForUser.cliffEnd)) {
            revert IVest.CliffExceedsPeriod();
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
        if(claimForUser.cliffEnd == 0){
            revert IVest.CliffDoesntExist();
        }
        _cliffChecks(claimForUser, newCliff);
        claimForUser.cliffEnd = newCliff;
    }

    function withdrawAccruedTokens(address claimee) public {
        ClaimData storage claimForUser = _userClaims[claimee];
        _accrueRewards(claimForUser, claimee);
        if(_claimableAmount[claimee] <= 0){
            revert IVest.NothingToClaim();
        }
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
            uint256 rewards = _calculateUserClaimableRewards(
                claimForUser,
                block.timestamp
            );
            totalClaimable -= rewards;
            claimForUser.dripped += rewards;
            _claimableAmount[claimee] += rewards;
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
}
