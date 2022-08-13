// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

struct ClaimData {
    uint256 totalVestedAmount;
    uint256 dripped;
    uint256 claimStart;
    uint256 claimEnd;
    uint256 cliffEnd;
    bool claimInvalid;
}
