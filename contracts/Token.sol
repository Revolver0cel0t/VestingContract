// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RevToken is ERC20  {
    
    constructor() ERC20("RevToken", "REV"){}

    function mintToUser(address user,uint256 amount) public{
        _mint(user, amount);
    }

    function approveFor(address spender,address owner, uint256 amount) public returns (bool) {
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _spendAllowance(from, to, amount);
        _transfer(from, to, amount);
        return true;
    }
}
