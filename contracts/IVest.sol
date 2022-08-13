// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Structs.sol";

interface IVest {
    
    //Errors defined here

    //Only allow expired claims
    error OnlyNonExpiredClaims();

    //Only owner allowed to access the particular functions
    error OnlyOwner();
    
    //Cant withdraw as it would lead to balances < claims
    error BalancesLowerThanClaims();

    //Token amount has to be greater than 0!
    error TokenAmountZero();

    //Claim already exists for this account
    error ClaimAlreadyExists();

    //That amount has already been vested to the user, restart claim to vest the same amt
    error AmountAlreadyDripped();

    //Cannot change claim amount as the total claims would exceed token reserves
    error ClaimAdditionExceedsReserves();

    //New claim period has to be greater than the current time
    error NewPeriodSmallerThanClaim();

    //New claim period has to be greater than the cliff
    error CliffExceedsPeriod();

    //Can only modify if cliff exists
    error CliffDoesntExist();

    //Nothing to claim
    error NothingToClaim();

    //Time is either greater than end period or lesser than start period
    error TimeSetWrong();

    //Incorrect cliff Params
    error IncorrectCliffParams();
}
