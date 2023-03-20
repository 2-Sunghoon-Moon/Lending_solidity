// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./IPriceOracle.sol";
import "./DreamOracle.sol";

contract DreamAcademyLending {
    address private _owner;
    DreamOracle private _orcale;


    ERC20 usdc;

    uint256 ethBalance;
    uint256 usdcBalance;


    constructor(IPriceOracle _ioracle, address _lendingToken) {
        _owner = msg.sender;
        _orcale = DreamOracle(address(_ioracle));

        usdc = ERC20(_lendingToken);
    }

    function initializeLendingProtocol(address t) payable external {
        require(_owner == msg.sender);

        usdc.transferFrom(msg.sender, address(this), msg.value);
        usdcBalance += msg.value;

    }

    function deposit(address tokenAddress, uint256 amount) payable external {
        console.log("[+] deposit");
        console.log("Token Addr: ", tokenAddress);


        if(tokenAddress == address(0x0)) {
            require(msg.value > 0);
            require(amount > 0);
            require(amount <= msg.value);

            ethBalance += amount;
        } else {
            // console.log("USDC Balance: ", usdc.balanceOf(address(this)));
            usdc.transferFrom(msg.sender, address(this), amount);

            usdcBalance += amount;
        }        


        console.log("ETH Balance: ", ethBalance / (10 ** 18));
        console.log("USDC Balance: ", usdcBalance / (10 ** 18));
        console.log("\n");
    }



    function borrow(address tokenAddress, uint256 amount) payable external {
        console.log("[+] borrow");
        console.log("Token Addr: ", tokenAddress);

        // ETH 대출
        if(tokenAddress == address(0x0)) {

        } 
        // USDC 대출
        else {
            uint256 ratio = _orcale.getPrice(address(0x0)) / _orcale.getPrice(address(tokenAddress));
            console.log("RATIO:", ratio);

            ERC20(tokenAddress).transfer(msg.sender, amount);
        }        
    }


    function repay(address tokenAddress, uint256 amount) external {

    }
    function liquidate(address user, address tokenAddress, uint256 amount) external {

    }
    function withdraw(address tokenAddress, uint256 amount) external {

    }

    function getAccruedSupplyAmount(address token) external pure returns (uint256) {

        return 0;

    }



}