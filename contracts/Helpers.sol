// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Structs.sol";
import "./Token.sol";
import "./IVest.sol";
import "hardhat/console.sol";

function _cliffChecks(ClaimData memory _claim, uint256 newCliff)
    pure
{
    if(_claim.cliffEnd >= newCliff || _claim.claimEnd <= newCliff){
        revert IVest.IncorrectCliffParams();
    }
    uint256 diff = (newCliff - _claim.claimStart) / 60 / 60 / 24;
    if(diff > 180) {
        revert IVest.IncorrectCliffParams();
    }
}

function _createChecks(
    uint256 amount,
    uint256 claimEndTimestamp,
    uint256 claimStartTimestamp,
    uint256 totalClaimable,
    address claimToken,
    address contractAddress
) view {
    if(amount<=0){
        revert IVest.TokenAmountZero();
    }
    if(claimEndTimestamp <= block.timestamp || claimEndTimestamp <= claimStartTimestamp){
        revert IVest.TimeSetWrong();
    }
    if(totalClaimable + amount >
        ERC20(claimToken).balanceOf(contractAddress)){
        revert IVest.ClaimAdditionExceedsReserves();
    }
}

function _remainingUserClaimableAmount(ClaimData memory _claim)
    pure
    returns (uint256)
{
    return _claim.totalVestedAmount - _claim.dripped;
}


function _calculateUserClaimableRewards(
    ClaimData memory claimForUser,
    uint256 currentTime
) view returns (uint256) {
    console.log("-------------");
    console.log("HH: Current time",currentTime);
    console.log("HH: claimStart",claimForUser.claimStart);
    console.log("HH: claimEnd",claimForUser.claimEnd);
    console.log("-------------");
    if (
        (currentTime < claimForUser.cliffEnd) ||
        claimForUser.claimStart == 0 || claimForUser.claimInvalid
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