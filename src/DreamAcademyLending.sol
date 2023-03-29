// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./IPriceOracle.sol";


contract DreamAcademyLending {
    address private _owner;
    IPriceOracle public orcale;

    uint32 public constant LIQUIDATION_THRESHOLD = 75;  // unit: percentage

    ERC20 USDC_TOKEN;
    ERC20 ETH_TOKEN;

    uint256 USDC_BALANCE;
    uint256 ETH_BALANCE;

    struct Ledger {
        uint256 ETH_collateral;
        uint256 USDC_balance;
        uint256 USDC_debt;
        uint256 USDC_borrow_time;
        uint256 USDC_interest;
    }


    mapping(address => Ledger) public ledgers;


    uint256 USDC_TOTAL_BORROW;
    uint256 USDC_TOTAL_DEPOSIT;
    uint256 USDC_TOTAL_DEBT;



    mapping(address => bool) public userState;
    address[] public users;


    struct InterestInfo {
        uint256 USDC_total_debt_before;
        uint256 USDC_total_debt;
        uint256 blockTime;
    }

    InterestInfo public _interInfo;


    constructor(IPriceOracle _ioracle, address _lendingToken) {
        _owner = msg.sender;
        orcale = _ioracle;

        USDC_TOKEN = ERC20(_lendingToken);
        ETH_TOKEN = ERC20(address(0x0));

        _interInfo.blockTime = block.number;
    }



    function _addUser(address _user) private {
        // console.log("_addUser()");
        // console.log(_user);

        if(!userState[_user]) {
            users.push(_user);

            userState[_user] = true;
        }
    }

    function initializeLendingProtocol(address token) payable external {
        require(_owner == msg.sender);


        USDC_TOKEN.transferFrom(msg.sender, address(this), msg.value);
        USDC_BALANCE += msg.value;
    }


    function _printUserLedger(address user) internal {
        console.log("[USER]");
        console.log("ETH_collateral: ", ledgers[user].ETH_collateral);
        console.log("USDC_balance: ", ledgers[user].USDC_balance);
        console.log("USDC_debt: ", ledgers[user].USDC_debt);
        console.log("USDC_borrow_time: ",ledgers[user].USDC_borrow_time);
        console.log("\n");
    }

    function _printLendingBalance() internal {
        console.log("ETH: ", address(this).balance);
        console.log("USDC: ", USDC_TOKEN.balanceOf(address(this)));
        console.log("\n");
    }


    function deposit(address tokenAddress, uint256 amount) payable external {
        console.log("[+] deposit");

        _addUser(msg.sender);
        _updateInterest(msg.sender);

        _printLendingBalance();

        require(amount > 0);
        require(tokenAddress == address(USDC_TOKEN) || tokenAddress == address(ETH_TOKEN));

        if(tokenAddress == address(ETH_TOKEN)) {
            require(0 < msg.value);
            require(amount <= msg.value);

            ledgers[msg.sender].ETH_collateral += amount;

        } else { // USDC TOKEN
            require(USDC_TOKEN.allowance(msg.sender, address(this)) >= amount);
            USDC_TOKEN.transferFrom(msg.sender, address(this), amount);

            ledgers[msg.sender].USDC_balance += amount;

            USDC_TOTAL_DEPOSIT += amount;
        }

        _printLendingBalance();
    }


    function borrow(address tokenAddress, uint256 amount) payable external {
        console.log("[+] borrow");

        _updateInterest(msg.sender);
        _addUser(msg.sender);

        require(tokenAddress == address(USDC_TOKEN));
        require(0 < amount);
        require(amount <= USDC_TOKEN.balanceOf(address(this)));


        uint256 USDC_collateral_LTV = ledgers[msg.sender].ETH_collateral * orcale.getPrice(address(ETH_TOKEN)) / 1e18 * 50 / 100;
        uint256 USDC_debt = ledgers[msg.sender].USDC_debt ;

        // 대출자의 경우 이전 대출양을 제외하고 대출해줘야 한다.
        console.log(USDC_collateral_LTV);
        console.log(USDC_debt);

        require(amount + USDC_debt <= USDC_collateral_LTV );

        USDC_TOKEN.transfer(msg.sender, amount);

        ledgers[msg.sender].USDC_debt += amount;
        ledgers[msg.sender].USDC_borrow_time = block.number;

        USDC_TOTAL_BORROW += amount;

        // 이자 설정
        _interInfo.USDC_total_debt += amount;
        _interInfo.blockTime = block.number;

        // console.log("USDC_TOTAL_DEBT: ", _interInfo.USDC_total_debt);
        // console.log("BLOCKTIME: ", _interInfo.blockTime);

        _printUserLedger(msg.sender);
    }


    // repay(address tokenAddress, uint256 amount)
    // DESC: 상환을 위한 함수
    // arg[0]: 상환하고자 하는 토큰의 주소
    // arg[1]: 상환금액
    // TODO: 이자율 고려해야 하는 것으로 보임
    function repay(address tokenAddress, uint256 amount) external {

        _addUser(msg.sender);
        _updateInterest(msg.sender);
        console.log("[+] repay()");
        console.log(" ledgers[msg.sender].USDC_debt", ledgers[msg.sender].USDC_debt);
        console.log(" ledgers[msg.sender].USDC_debt", ledgers[msg.sender].USDC_debt);
        
        
        require(tokenAddress == address(USDC_TOKEN), "1");
        require(amount > 0 , "2");
        require(USDC_TOKEN.allowance(msg.sender, address(this)) >= amount, "3");
        

        _interInfo.USDC_total_debt -= amount;
        ledgers[msg.sender].USDC_debt -= amount;
        console.log("AFTER REAPY: ", ledgers[msg.sender].USDC_debt);

        USDC_TOKEN.transferFrom(msg.sender, address(this), amount);
    }



    // liquidate(address user, address tokenAddress, uint256 amount)
    // DESC: 강제 청산을 진행하는 함수 청산을 요구한 사람이 담보에 해당하는 만큼의 금액을 가져갈 수 있으며 제공한 비용은 프로토콜에서
    //       가져갈 수 있도록 한다.
    // arg[0]: 고객
    // arg[1]: 토큰의 종류
    // arg[2]: 청산하고자 하는 양
    function liquidate(address user, address tokenAddress, uint256 amount) external {
        _addUser(msg.sender);
        _updateInterest(msg.sender);

        console.log("[+] liquidate()");
        console.log("    amount: ", amount);
        console.log("    user debt: ", ledgers[user].USDC_debt);
        console.log("    user_collateral_ETH", ledgers[user].ETH_collateral * orcale.getPrice(address(ETH_TOKEN)) / orcale.getPrice(address(USDC_TOKEN)));


        uint256 test = ledgers[user].USDC_debt * 100 / (ledgers[user].ETH_collateral * orcale.getPrice(address(ETH_TOKEN)) / orcale.getPrice(address(USDC_TOKEN)));
        console.log("colleral_ratio: ", test);   // => (대출한 USDC / 담보물의 가치) > (75 / 100)


        // [1] 담보가치가 75% 이상 여부에 대한 검증 
        require(test >= 75, "liquidation hold is 75");

        if(test >= 75) {
            console.log("can liquidate!");
        } else {
            console.log("can't liquidate!");
        }


        // [2]
        if(ledgers[user].USDC_debt <= 100 ether) {
            //
        } else {
            console.log("25% only");
            // console.log();
            // console.log(amount);

            require(amount * 4 <= ledgers[user].USDC_debt);

            ledgers[user].USDC_debt -= amount;
            
        }




        // // 청산가능한 형태인지 확인
        // uint256 USDC_collateral = ledgers[user].ETH_collateral * orcale.getPrice(address(ETH_TOKEN)) / 10 ** 18;
        // uint256 USDC_debt = ledgers[user].USDC_debt;

        // require(USDC_collateral * 75 /100 < USDC_debt, "bad loan");

        // [-] 미구현

    }

    // withdraw(address tokenAddress, uint256 amount)
    // DESC: 금액을 인출하는 함수, 단 이자율을 고려해야 한다.
    // arg[0]: 인출하고자 하는 토큰
    // arg[1]: 인출하고자 하는 금액
    function withdraw(address tokenAddress, uint256 amount) payable external {
        console.log("[+] withdraw");
        console.log(amount);
        _addUser(msg.sender);
        _updateInterest(msg.sender);

        _printLendingBalance();


        require(0 < amount);
        require(tokenAddress == address(USDC_TOKEN) || tokenAddress == address(ETH_TOKEN));

        if(tokenAddress == address(ETH_TOKEN)) {
            if(ledgers[msg.sender].USDC_debt != 0) { // 빚이 존재할 경우 환산해보자
                require(ledgers[msg.sender].USDC_debt * orcale.getPrice(address(USDC_TOKEN)) / orcale.getPrice(address(ETH_TOKEN)) * 1e28 
                        <= (ledgers[msg.sender].ETH_collateral - amount) * 1e28 * 75 / 100 );

                ledgers[msg.sender].ETH_collateral -= amount;

                (bool success, ) = payable(msg.sender).call{value: amount}("");

                require(success);
            } 
            
            else {
                require(amount <= ledgers[msg.sender].ETH_collateral);

                ledgers[msg.sender].ETH_collateral -= amount;

                (bool success, ) = payable(msg.sender).call{value: amount}("");

                require(success);
            }
        } else { // USDC TOKEN
            require(amount <= ledgers[msg.sender].USDC_balance + ledgers[msg.sender].USDC_interest);
            if(amount <= ledgers[msg.sender].USDC_balance) {
                USDC_TOKEN.transfer(msg.sender, amount);
                ledgers[msg.sender].USDC_balance - amount;
            } else {
                uint256 withdrawInterest = (ledgers[msg.sender].USDC_balance + ledgers[msg.sender].USDC_interest) - amount;

                USDC_TOKEN.transfer(msg.sender, amount);


                ledgers[msg.sender].USDC_interest -= withdrawInterest;

            }
        }
    }


    function getAccruedSupplyAmount(address token) external returns (uint256) {
        _updateInterest(msg.sender);
        
        return ledgers[msg.sender].USDC_balance;    
    }


    function _updateInterest(address _user) private {
        uint256 _blockPeriod = block.number - _interInfo.blockTime;


        if(_blockPeriod > 0) {
            uint256 interestAfter = test2(_interInfo.USDC_total_debt, _blockPeriod) / 10 ** 9;
            // console.log(interestAfter);

            for(uint256 i=0; i<users.length; i++) {
                if(ledgers[users[i]].USDC_balance != 0) {
                    uint256 user_interest = (interestAfter * 1e24 - _interInfo.USDC_total_debt * 1e24) * ledgers[users[i]].USDC_balance / USDC_TOTAL_DEPOSIT;
                    ledgers[users[i]].USDC_balance = ledgers[users[i]].USDC_balance + user_interest  / 1e24;
                }

                if(_interInfo.USDC_total_debt != 0) {
                    if(ledgers[users[i]].USDC_debt != 0) {
                        uint256 user_debt = ((interestAfter * 1e24 - ledgers[users[i]].USDC_debt * 1e24) * ledgers[users[i]].USDC_debt / _interInfo.USDC_total_debt);
                        ledgers[users[i]].USDC_debt = ledgers[users[i]].USDC_debt + user_debt / 1e24;
                        console.log(ledgers[users[i]].USDC_debt);
                    }
                }
            }

            _interInfo.USDC_total_debt_before = _interInfo.USDC_total_debt;
            _interInfo.USDC_total_debt = interestAfter;
            _interInfo.blockTime = block.number;
        } 


        console.log("END INTEREST[+]");
    }




    function _calculateUserInterest(uint256 amount, address _user) private {
        for(uint256 i=0; i<users.length; i++) {
            uint256 user_interest = amount * 1e24 * ledgers[users[i]].USDC_balance / USDC_TOTAL_DEPOSIT ;
            ledgers[users[i]].USDC_balance = (ledgers[users[i]].USDC_balance * 1e24 + user_interest) / 1e24 ;
        }
    }





    // 현재 이자만 업데이트 해보자
    function _updateUserLedger(address user, uint256 usdc_b) private {
        ledgers[user].USDC_balance = usdc_b;
    }




    function test2(uint256 _amountUSDC, uint256 _blockPeriod) internal returns(uint256) {
        uint256 interest;

        uint256 blockDay = _blockPeriod / 7200;
        uint256 blockSequence  = _blockPeriod % 7200;


        uint256 _borrowAmount = _amountUSDC;

        if(blockDay != 0) {
            interest += mul(_borrowAmount, rpow(1001 * RAY / 1000, blockDay));
        }
        if(blockSequence != 0) {
            interest += mul(_borrowAmount, rpow(1000000138819500339398888888, blockSequence));
        }
        
        return interest / 1e18;    
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