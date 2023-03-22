// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./IPriceOracle.sol";
import "./DreamOracle.sol";

contract DreamAcademyLending {
    address private _owner;
    DreamOracle private _orcale;

    ERC20 tokenUSDC;
    ERC20 tokenETH;

    uint256 ETHBalance;               // 대출 시스템에 예치된 ETH의 보유량    (deposit, borrow, withdraw 영향)
    uint256 USDCBalance;              // 대출 시스템에 예치된 USDC의 보유량   (deposit, borrow, withdraw 영향)


    uint256 ETHtotalBorrow;           // 총 대출해간 ETH의 양
    uint256 USDCtotalBorrow;          // 총 대출해간 USDC의 양


    uint32 public constant LTV = 50;                   // unit: percentage
    uint32 public constant INTEREST_RATE = 1;          // unit: percentage
    uint32 public constant LIQUIDATION_THRESHOLD = 75;  // unit: percentage


    struct AccountBook {
        uint256 eth_balance;
        uint256 usdc_balance;
        uint256 eth_deposit;
        uint256 usdc_deposit;
        uint256 eth_borrow;
        uint256 usdc_borrow;

        uint256 eth_interest;
        uint256 usdc_interest;

        uint256 eth_collateral;
    }


    address[] particpants;                                  // 해당 시스템의 참여자
    mapping(address => bool) public participateState;       // 주소의 참여여부
    mapping(address => AccountBook) public participateBooks;    // 유저의 예금/대출/잔액 이력


    uint256 private _prevBlockTime;
    uint256 private _latestBlockTime;



    function debugBook(address user) public {
        console.log("[",user,"]");
        console.log("[ETH_DEPOSIT]: ", participateBooks[user].eth_deposit / 1e18);
        console.log("[USDC_DEPOSIT]: ", participateBooks[user].usdc_deposit /1e18);
        console.log("[ETH_BORROW]: ", participateBooks[user].eth_borrow / 1e18);
        console.log("[USDC_BORROW]: ", participateBooks[user].usdc_borrow / 1e18);
    }


    constructor(IPriceOracle _ioracle, address _lendingToken) {
        _owner = msg.sender;
        _orcale = DreamOracle(address(_ioracle));

        tokenUSDC = ERC20(_lendingToken);
        // tokenETH = ERC20(address(0x0));
    }


    function initializeLendingProtocol(address t) payable external {
        require(_owner == msg.sender);

        tokenUSDC.transferFrom(msg.sender, address(this), msg.value);
        USDCBalance += msg.value;
    }


    function deposit(address tokenAddress, uint256 amount) payable external {
        console.log("[+] deposit");
        console.log("Token Addr: ", tokenAddress);


        // 참여자 정보 생성
        _createBook(msg.sender);

        _updateInterest();

        if(tokenAddress == address(0x0)) {
            require(msg.value > 0);
            require(amount > 0);
            require(amount <= msg.value);

            ETHBalance += amount;

            participateBooks[msg.sender].eth_balance += amount;
            participateBooks[msg.sender].eth_deposit += amount;
            participateBooks[msg.sender].eth_collateral += amount;
        } else {
            require(tokenUSDC.allowance(msg.sender, address(this)) > amount);
            tokenUSDC.transferFrom(msg.sender, address(this), amount);

            USDCBalance += amount;

            participateBooks[msg.sender].usdc_balance += amount;
            participateBooks[msg.sender].usdc_deposit += amount;
        }        

        debugBook(msg.sender);
        console.log("ETH Balance: ", ETHBalance / (10 ** 18));
        console.log("USDC Balance: ", USDCBalance / (10 ** 18));
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


        // 참여자 정보 생성
        _createBook(msg.sender);
        _updateInterest();
        // ETH 대출
        if(tokenAddress == address(0x0)) {
            // USDC -> ETH 대출 불가
            revert();
        } 
        // USDC 대출
        else {
            uint256 ratio = _orcale.getPrice(address(0x0)) / _orcale.getPrice(address(tokenAddress));   


            // 차용가능한 금액 환산
            uint256 borrowedUSDC = participateBooks[msg.sender].usdc_balance;
            uint256 borrowableUSDC = participateBooks[msg.sender].eth_balance * ratio / 2;

            borrowableUSDC = borrowableUSDC - borrowedUSDC;   // LTV 고려
            console.log("borrowABLEAMOUNT", borrowableUSDC / 1e18);
            
            require(amount <= USDCBalance);              // 대출하고자 하는 금액이 Lending에 존재해야 한다.
            require(amount <= borrowableUSDC);         // LTV(50%)를 고려하여 빌릴 수 있는 양 예시) 1이더 -> 669.5USDC 빌림(LTV 50%)


            ERC20(tokenAddress).transfer(msg.sender, amount);

            USDCBalance -= amount;
            participateBooks[msg.sender].usdc_balance += amount;
            participateBooks[msg.sender].usdc_borrow += amount;
            USDCtotalBorrow += amount;
        }       

        debugBook(msg.sender);
        console.log("ETH Balance: ", ETHBalance / (10 ** 18));
        console.log("USDC Balance: ", USDCBalance / (10 ** 18));
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


        require(amount > 0);

        // 참여자 정보 생성
        _createBook(msg.sender);
        _updateInterest();

        if(tokenAddress == address(0x0)) {
            revert();
        } else {
            require(tokenUSDC.allowance(msg.sender, address(this)) >= amount);
            
            participateBooks[msg.sender].usdc_borrow -= amount;
            tokenUSDC.transferFrom(msg.sender, address(this), amount);
        }
        

        console.log("ETH Balance: ", ETHBalance / (10 ** 18));
        console.log("USDC Balance: ", USDCBalance / (10 ** 18));
        console.log("\n"); 

        // 이자 = 빌린금액 * (0.1 * blocktime / 1시간)
        // 갚아야하는 돈 = 빌린금액 * (1 + 0.1*blocktime/1시간)
    }



    // liquidate(address user, address tokenAddress, uint256 amount)
    // DESC: 강제 청산을 진행하는 함수 청산을 요구한 사람이 담보에 해당하는 만큼의 금액을 가져갈 수 있으며 제공한 비용은 프로토콜에서
    //       가져갈 수 있도록 한다.
    // arg[0]: 고객
    // arg[1]: 토큰의 종류
    // arg[2]: 청산하고자 하는 양
    function liquidate(address user, address tokenAddress, uint256 amount) external {
        console.log("[+] liquidate");
        console.log("USER: ", user);
        console.log("TOKEN ADDR: ", tokenAddress);
        console.log("AMOUNT: ", amount);
        _createBook(msg.sender);


        require(amount > 0);

        if(tokenAddress == address(0x0)) {
            revert();
        } else {
            uint256 ratio = _orcale.getPrice(address(0x0)) / _orcale.getPrice(address(tokenAddress)); 

            require((participateBooks[user].usdc_borrow * 25)  >= amount * 100);
            require(ratio * participateBooks[user].eth_collateral * LIQUIDATION_THRESHOLD < participateBooks[user].usdc_borrow * 100);

            uint256 amountETH = amount * participateBooks[user].eth_collateral / participateBooks[user].usdc_borrow;
            

            require(tokenUSDC.allowance(msg.sender, address(this)) >= amount);

            participateBooks[user].usdc_borrow -= amount;
            tokenUSDC.transferFrom(msg.sender, address(this), amount);
            payable(msg.sender).transfer(amountETH);

        }
    }



    function _createBook(address p) internal {
        if(!participateState[p]) {
            particpants.push(p);
            participateBooks[p] = AccountBook(0,0,0,0,0,0,0,0,0);
            participateState[p] = true;
        }

    }

    // withdraw(address tokenAddress, uint256 amount)
    // DESC: 금액을 인출하는 함수, 단 이자율을 고려해야 한다.
    // arg[0]: 인출하고자 하는 토큰
    // arg[1]: 인출하고자 하는 금액
    function withdraw(address tokenAddress, uint256 amount)  external {
        console.log("[+] withdraw()");
        console.log("address: ", tokenAddress);
        console.log("amount: ", amount);
        console.log("ETH Balance: ", ETHBalance / (10 ** 18));
        console.log("USDC Balance: ", USDCBalance / (10 ** 18));
        console.log("\n"); 


        // 참여자 정보 생성
        _createBook(msg.sender);

        _updateInterest();

        if(tokenAddress == address(0x0)) {
            require(ETHBalance >= amount);  
            

            // 인출로직 청산비율 고려해서 작성해야함
            uint256 borrowedETH = participateBooks[msg.sender].usdc_borrow  * 2 / _orcale.getPrice(address(0x0)) * 1e18;
            console.log(participateBooks[msg.sender].eth_balance - borrowedETH);

            require(participateBooks[msg.sender].eth_balance - borrowedETH >= amount);  

            (bool success, ) = payable(msg.sender).call{value: amount}("");

            ETHBalance -= amount;
            
            participateBooks[msg.sender].eth_balance -= amount;
            participateBooks[msg.sender].eth_deposit -= amount;
            participateBooks[msg.sender].eth_collateral -= amount;


        } else {
            require(USDCBalance >= amount); 
            require(participateBooks[msg.sender].usdc_balance + participateBooks[msg.sender].usdc_interest >= amount); 


            // 인출을 요청하는 USDC가 이자를 제외하고 추출이 가능한 경우
            if(participateBooks[msg.sender].usdc_balance < amount) {
                console.log("WITH INTEREST: ", amount);
                tokenUSDC.transfer(msg.sender, amount);

                require(participateBooks[msg.sender].usdc_interest >= (amount - participateBooks[msg.sender].usdc_balance));

                participateBooks[msg.sender].usdc_interest -= (amount - participateBooks[msg.sender].usdc_balance);
                participateBooks[msg.sender].usdc_balance = 0;
                participateBooks[msg.sender].usdc_deposit = 0;

            } else {
                tokenUSDC.transfer(msg.sender, amount);
                
                participateBooks[msg.sender].usdc_balance -= amount;
                participateBooks[msg.sender].usdc_deposit -= amount;
            }
            
            
            USDCBalance -= amount;
        }


            
        



        debugBook(msg.sender);
        console.log("ETH Balance: ", ETHBalance / (10 ** 18));
        console.log("USDC Balance: ", USDCBalance / (10 ** 18));
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



    // 참여자의 이자를 업데이트 한다.
    function _updateInterest() internal {
        // console.log("[+] UPDATE");
        uint256 _user_principal;  // 참여자의 원금
        uint256 _user_interest;   // 참여자의 이자

        for(uint256 i=0; i<particpants.length; i++) {
            // console.log("[P] ", particpants[i]);

            AccountBook memory book = participateBooks[particpants[i]];

            if(book.eth_deposit == 0 && book.usdc_deposit == 0) {
                continue;
            } else {
                //
                uint256 blockDays = (block.number - uint256(1)) / 7200 ;

                uint256 prime = USDCtotalBorrow;
                uint256 prime_interest = calculateInterest(prime, blockDays);  // 이자 계산

                uint256 result = (book.usdc_deposit / 1e18 * RAY) + (prime_interest - (prime * RAY / 1e18)) * 
                        book.usdc_deposit / (USDCBalance + USDCtotalBorrow) ;   // 지분율

                _user_interest = (result * 1e18 / RAY) - book.usdc_deposit;


                participateBooks[particpants[i]].usdc_interest = _user_interest;
            }
        }

    } 


    function getAccruedSupplyAmount(address token) external returns (uint256) {
        _updateInterest();

        if(participateState[msg.sender]) {
            console.log(participateBooks[msg.sender].usdc_deposit + participateBooks[msg.sender].usdc_interest);
            return participateBooks[msg.sender].usdc_deposit + participateBooks[msg.sender].usdc_interest;
        } else {
            return 0;
        }

        // uint256 blockDays = (block.number - uint256(1)) / 7200 ; // 몇일 흘렀는지

        // uint256 prime = USDCtotalBorrow;
        // uint256 prime_interest = calculateInterest(prime, blockDays);  // 이자 계산

        // uint256 result = (participateBooks[msg.sender].usdc_deposit / 1e18 * RAY) + (prime_interest - (prime * RAY / 1e18)) * 
        //                 participateBooks[msg.sender].usdc_deposit / (USDCBalance + USDCtotalBorrow) ;   // 지분율



        
    }


    // 이자를 포함하여 계산하는 함수
    // arg[0]: 빌려간 금액에 대해서 입력하는 정보 (ether 단위 아님)
    // arg[1]: 블록시간을 계산하여 몇 일이 지났는지에 대한 정보
    function calculateInterest(uint256 borrowAmount, uint256 blockPeriodDays) internal returns (uint256) {
        // console.log("[+] calculateInterest()");
        // console.log("    borrowAmount: ", borrowAmount);
        // console.log("    blockPeriodDays: ", blockPeriodDays);

        uint256 _borrowAmount = borrowAmount / 1e18;  // 보정
        uint256 interest = mul(_borrowAmount, rpow(1001 * RAY / 1000, blockPeriodDays));

        return interest;
    }








    // https://github.com/wolflo/solidity-interest-helper
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