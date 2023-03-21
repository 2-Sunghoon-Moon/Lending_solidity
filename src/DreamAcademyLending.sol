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
    ERC20 eth;

    uint256 ethBalance;
    uint256 usdcBalance;


    uint32 public constant LTV = 50;                   // unit: percentage
    uint32 public constant INTEREST_RATE = 1;          // unit: percentage
    uint32 public constant LIQUIDATION_THRESHOLD = 75;  // unit: percentage


    struct AccountBook {
        uint256 eth_deposit;
        uint256 usdc_deposit;
        uint256 eth_borrow;
        uint256 usdc_borrow;
    }



    mapping(address => uint256) public depositETH;      // deposit한 사람들의 금액(ETH)정보
    mapping(address => uint256) public depositUSDC;     // deposit한 사람들의 금액(USDC)정보
 
    // mapping(address => mapping(uint256 => uint256)) public depositTimestamp; // USDC를 대출한 시간정보를 기억함


    // 대출정보를 잘 조회하기 위해서는 어떤 자료 구조가 필요할까?
    mapping(address => AccountBook) public accountBooks;


    uint256 private _prevBlockTime;
    uint256 private _latestBlockTime;



    function debugBook(address user) public {
        console.log("[",user,"]");
        console.log("[ETH_DEPOSIT]: ", accountBooks[user].eth_deposit / 1e18);
        console.log("[USDC_DEPOSIT]: ", accountBooks[user].usdc_deposit /1e18);
        console.log("[ETH_BORROW]: ", accountBooks[user].eth_borrow / 1e18);
        console.log("[USDC_BORROW]: ", accountBooks[user].usdc_borrow / 1e18);
    }


    constructor(IPriceOracle _ioracle, address _lendingToken) {
        _owner = msg.sender;
        _orcale = DreamOracle(address(_ioracle));

        usdc = ERC20(_lendingToken);
        eth = ERC20(address(0x0));
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

            // eth.transferFrom(msg.sender, address(this), amount);

            ethBalance += amount;
            depositETH[msg.sender] += amount;
            accountBooks[msg.sender].eth_deposit += amount;
        } else {
            // console.log("USDC Balance: ", usdc.balanceOf(address(this)));
            usdc.transferFrom(msg.sender, address(this), amount);

            usdcBalance += amount;
            depositUSDC[msg.sender] += amount;
            accountBooks[msg.sender].usdc_deposit += amount;
        }        

        debugBook(msg.sender);
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
            // borrowHistory[msg.sender].push(History(amount, block.number));

            
            // 빌린금액을 사용자의 ETH에서 차감해야 한다.
            // console.log("amount to ETH: ", depositETH[msg.sender] * amount / borrowableAmount);   // 1000 USDC를 빌림 ->

            depositETH[msg.sender] -= depositETH[msg.sender] * amount / borrowableAmount;         // [문제] 나누기 3이 들어가기 때문에 숫자 정밀도에서 오류가 발생할 수 있음
            // console.log(depositETH[msg.sender]);
            accountBooks[msg.sender].usdc_borrow += amount;

        }       

        debugBook(msg.sender);
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
            // console.log(borrowHistory[msg.sender].length);
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
    function withdraw(address tokenAddress, uint256 amount) payable external {
        console.log("[+] withdraw()");
        console.log("address: ", tokenAddress);
        console.log("amount: ", amount);

        ERC20 token = ERC20(tokenAddress);

        if(tokenAddress == address(0x0)) {
            console.log(depositETH[msg.sender]);
            console.log(address(this).balance);
            require(depositETH[msg.sender] >= amount);    
            console.log(address(this).balance >= amount);
            (bool success, ) = msg.sender.call{value: amount}("");

            console.log(success);

            ethBalance -= amount;
            depositETH[msg.sender] -= amount;
            accountBooks[msg.sender].eth_deposit -= amount;

            console.log("========================================");

        } else {
            require(depositUSDC[msg.sender] >= amount); 
            token.transfer(msg.sender, amount);


            usdcBalance -= amount;
            depositUSDC[msg.sender] -= amount;
            accountBooks[msg.sender].usdc_deposit -= amount;
        }


            
        



        debugBook(msg.sender);
        console.log("ETH Balance: ", ethBalance / (10 ** 18));
        console.log("USDC Balance: ", usdcBalance / (10 ** 18));
        console.log("\n"); 
    }





    function calculate(uint256 p, uint256 rate_n, uint256 rate_d, uint256 n) internal returns (uint256) { 
        require(p >= 1000);
        require(rate_n > rate_d); 

        
        // [VERSION 2]
        // uint256 t1 = (rate_n ** n) - (rate_d ** n);
        // uint256 t2 = rate_d ** (n);
        // uint256 t3 = rate_n - rate_d;
        // uint256 t4 = rate_d;


        // require(((p / 1000) * (t1 * t4)) > (t2 * t3));

        // uint256 result = ((p / 1000) * (t1 * t4)) / (t2 * t3);
        // result += p;


        // [VERSION3]
        // uint256 t1 = rate_d * ((rate_n / rate_d) ** n - 1);      // -> rate_n과 rate_d를 나누면 1로 수렴하게된다. 방법이 없을까?
        // uint256 t2 = rate_n - rate_d;

        // uint256 result = t1 / t2;
        // result += p;

        uint256 test = rpow(1001, 1000);

        return test;
    }





    function getAccruedSupplyAmount(address token) external returns (uint256) {
        console.log("[+] getAccruedSupplyAmount()");
        console.log("    block_time: ", block.number);



        uint256 blockDays = (block.number - uint256(1)) / 7200 ; // 몇일 흘렀는지

        uint256 prime = 2000 ether;   // 빌려간 금액
        uint256 prime_interest = calculateInterest(prime, blockDays);  // 이자 계산

        uint256 result = ((30000000 * RAY) + (prime_interest - (prime * RAY / 1e18)) * 3 / 13 );   // 지분율 고려
        
        // console.log(result * 1e18 / RAY);


        return result * 1e18 / RAY;
    }


    // 이자를 포함하여 계산하는 함수
    // arg[0]: 빌려간 금액에 대해서 입력하는 정보 (ether 단위 아님)
    // arg[1]: 블록시간을 계산하여 몇 일이 지났는지에 대한 정보
    function calculateInterest(uint256 borrowAmount, uint256 blockPeriodDays) internal returns (uint256) {
        console.log("[+] calculateInterest()");
        console.log("    borrowAmount: ", borrowAmount);
        console.log("    blockPeriodDays: ", blockPeriodDays);

        uint256 _borrowAmount = borrowAmount / 1e18;  // 보정
        uint256 interest = mul(_borrowAmount, rpow(1001 * RAY / 1000, blockPeriodDays));

        return interest;
    }








    // https://github.com/dapphub/ds-math
    uint constant RAY = 10 ** 27;

    function add(uint x, uint y) internal view returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function mul(uint x, uint y) internal view returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function div(uint x, uint y) public view returns (uint){
        return x / y;
    }

    function rmul(uint x, uint y) public view returns (uint z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }

    function rpow(uint x, uint n) internal returns (uint z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }


}