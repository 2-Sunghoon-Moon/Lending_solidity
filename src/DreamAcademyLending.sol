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


    uint32 public constant LTV = 50;                   // unit: percentage
    uint32 public constant INTEREST_RATE = 1;          // unit: percentage
    uint32 public constant LIQUIDATION_THRESHOLD = 75;  // unit: percentage


    struct History {
        uint256 amount;            // 대출금
        uint256 time;              // 대출일시
    }



    mapping(address => uint256) public depositETH;      // deposit한 사람들의 금액(ETH)정보
    mapping(address => uint256) public depositUSDC;     // deposit한 사람들의 금액(USDC)정보
 
    // mapping(address => mapping(uint256 => uint256)) public depositTimestamp; // USDC를 대출한 시간정보를 기억함


    // 대출정보를 잘 조회하기 위해서는 어떤 자료 구조가 필요할까?
    mapping(address => History[]) public borrowHistory;






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
            depositETH[msg.sender] += amount;
        } else {
            // console.log("USDC Balance: ", usdc.balanceOf(address(this)));
            usdc.transferFrom(msg.sender, address(this), amount);

            usdcBalance += amount;
            depositUSDC[msg.sender] += amount;
        }        


        console.log("ETH Balance: ", ethBalance / (10 ** 18));
        console.log("USDC Balance: ", usdcBalance / (10 ** 18));
        console.log("\n");
    }



    // borrow(address tokenAddress, uint256 amount)
    // DESC: 대출에 대한 요청자에게 원하는 토큰을 대출해주는 함수
    // arg[0]: 대출 받고자 하는 토큰의 종류를 의미
    // arg[1]: 대출 받고자 하는 양을 의미 
    function borrow(address tokenAddress, uint256 amount) payable external {
        console.log("[+] borrow");
        console.log("Token Addr: ", tokenAddress);
        console.log("TIME_STAMP: ", block.number);
        console.log("AMOUNT: ", amount / (10 ** 18));



        // ETH 대출
        if(tokenAddress == address(0x0)) {

        } 
        // USDC 대출
        else {
            uint256 ratio = _orcale.getPrice(address(0x0)) / _orcale.getPrice(address(tokenAddress));   
            // console.log("RATIO:", ratio);

            uint256 borrowableAmount = depositETH[msg.sender] * ratio * 50 / 100;

            console.log("BorrowableAmount: ", borrowableAmount / 10 ** 18);

            
            require(amount <= borrowableAmount);         // LTV(50%)를 고려하여 빌릴 수 있는 양 예시) 1이더 -> 669.5USDC 빌림(LTV 50%)
            require(amount <= usdcBalance);              // 대출하고자 하는 금액이 Lending에 존재해야 한다.
            // require(depositTimestamp[msg.sender] == 0);  // 대출한 여부가 없어야 한다.


            ERC20(tokenAddress).transfer(msg.sender, amount);

            usdcBalance -= amount;
            // 돈빌린 정보 기억할 수 있어야 한다.
            // 얼마의 ETH를 통해서 USDC 빌렸는지 언제 빌렸는지
            // mapping(address => History[]) public borrowHistory;
            borrowHistory[msg.sender].push(History(amount, block.number));

            
            // 빌린금액을 사용자의 ETH에서 차감해야 한다.
            // console.log("amount to ETH: ", depositETH[msg.sender] * amount / borrowableAmount);   // 1000 USDC를 빌림 ->

            depositETH[msg.sender] -= depositETH[msg.sender] * amount / borrowableAmount;         // [문제] 나누기 3이 들어가기 때문에 숫자 정밀도에서 오류가 발생할 수 있음
            // console.log(depositETH[msg.sender]);

        }       


        console.log("ETH Balance: ", ethBalance / (10 ** 18));
        console.log("USDC Balance: ", usdcBalance / (10 ** 18));
        console.log("\n"); 
    }


    // repay(address tokenAddress, uint256 amount)
    // DESC: 상환을 위한 함수
    // arg[0]: 상환하고자 하는 토큰의 주소
    // arg[1]: 상환금액
    // TODO: 이자율 고려해야 하는 것으로 보임
    function repay(address tokenAddress, uint256 amount) external {
        console.log("[+] repay");
        console.log("Token Addr: ", tokenAddress);
        console.log("AMOUNT: ", amount / (10 ** 18));
         console.log("TIME_STAMP: ", block.number);


        // require(실제 repay하는 사람이 돈을 빌린사람인가 확인)

        if(tokenAddress == address(0x0)) {

        } 
        // USDC 상환
        else {
            uint256 ratio = _orcale.getPrice(address(0x0)) / _orcale.getPrice(address(tokenAddress));  
            console.log("REPAY_MONEY: 0.", amount * 2 / ratio / 10 ** 17);
        
            require(ERC20(tokenAddress).allowance(msg.sender, address(this)) >=  amount * 2 / ratio);  // 돈 실제로 상환했는 지 검증

            ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount * 2 / ratio);
            depositETH[msg.sender] += amount * 2 / ratio;                 // 상환한 ETH 개인계정에 추가

            // borrowHistory[msg.sender].push(History(amount, block.time));
            console.log(borrowHistory[msg.sender].length);
        }


        console.log("ETH Balance: ", ethBalance / (10 ** 18));
        console.log("USDC Balance: ", usdcBalance / (10 ** 18));
        console.log("\n"); 

        // 이자 = 빌린금액 * (0.1 * blocktime / 1시간)
        // 갚아야하는 돈 = 빌린금액 * (1 + 0.1*blocktime/1시간)
    }



    // liquidate(address user, address tokenAddress, uint256 amount)
    // DESC: 강제 청산을 진행하는 함수
    // arg[0]: 고객
    // arg[1]: 토큰의 종류
    // arg[2]: 청산하고자 하는 양
    function liquidate(address user, address tokenAddress, uint256 amount) external {

    }





    // withdraw(address tokenAddress, uint256 amount)
    // DESC: 금액을 인출하는 함수, 단 이자율을 고려해야 한다.
    // arg[0]: 인출하고자 하는 토큰
    // arg[1]: 인출하고자 하는 금액
    function withdraw(address tokenAddress, uint256 amount) external {

    }


    function getAccruedSupplyAmount(address token) external view returns (uint256) {
        console.log("[+] getAccruedSupplyAmount()");
        console.log("    block_time: ", block.number);


        console.log(" ");

        return 0;
    }

    function calculate(uint256 p, uint256 rate_n, uint256 rate_d, uint256 n) external returns (uint256) { 
        require(p > 10000);
        require(rate_n > rate_d);   // 이게 진정한 rate다.

       
        // p: 원금
        // rate: 소수
        // n: 지난 시간

        // k = p / 1000
        // _n = (rate ** n) - 1
        // _d = rate - 1
        // 결과 = p + k*(_n/d) 
        ///////////////////////////////////////////

        
        // [VERSION 2]
        uint256 t1 = (rate_n ** n) - (rate_d ** n);
        uint256 t2 = rate_d ** (n);
        uint256 t3 = rate_n - rate_d;
        uint256 t4 = rate_d;


        require(((p / 1000) * (t1 * t4)) > (t2 * t3));

        uint256 result = ((p / 1000) * (t1 * t4)) / (t2 * t3);
        result += p;
        // console.log(p);




        // [VERSION 3]

        // console.log(((rate_n**n)/(rate_d**n)));

        // uint256 t1 = rate_d * (((rate_n**n)/(rate_d**n)) - 1);
        // uint256 t2 = rate_n - rate_d;

        // uint256 result = t1 / t2 + p;

        console.log(result);
    }




    function log2(uint x) public returns (uint256 y) {
        assembly {
            let arg := x
            x := sub(x,1)
            x := or(x, div(x, 0x02))
            x := or(x, div(x, 0x04))
            x := or(x, div(x, 0x10))
            x := or(x, div(x, 0x100))
            x := or(x, div(x, 0x10000))
            x := or(x, div(x, 0x100000000))
            x := or(x, div(x, 0x10000000000000000))
            x := or(x, div(x, 0x100000000000000000000000000000000))
            x := add(x, 1)
            let m := mload(0x40)
            mstore(m,           0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd)
            mstore(add(m,0x20), 0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe)
            mstore(add(m,0x40), 0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616)
            mstore(add(m,0x60), 0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff)
            mstore(add(m,0x80), 0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e)
            mstore(add(m,0xa0), 0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707)
            mstore(add(m,0xc0), 0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606)
            mstore(add(m,0xe0), 0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100)
            mstore(0x40, add(m, 0x100))
            let magic := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
            let shift := 0x100000000000000000000000000000000000000000000000000000000000000
            let a := div(mul(x, magic), shift)
            y := div(mload(add(m,sub(255,a))), shift)
            y := add(y, mul(256, gt(arg, 0x8000000000000000000000000000000000000000000000000000000000000000)))
        }  
    }

}