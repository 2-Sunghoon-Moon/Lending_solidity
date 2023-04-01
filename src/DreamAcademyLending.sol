// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./IPriceOracle.sol";


contract DreamAcademyLending {
    address private _owner;
    IPriceOracle public oracle;

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

    
    // [이벤트 정의]
    event Deposit(address indexed user, address indexed toeknAddress, uint256 indexed amount);
    event Borrow(address indexed user, uint256 indexed amount);
    event Repay(address indexed user, uint256 indexed amount);
    event Liquidate(address indexed user, address indexed targetUser, uint256 indexed amount);
    event Withdraw(address indexed user, address indexed toeknAddress, uint256 indexed amount);

 
    constructor(IPriceOracle _ioracle, address _lendingToken) {
        _owner = msg.sender;
        oracle = _ioracle;

        USDC_TOKEN = ERC20(_lendingToken);
        ETH_TOKEN = ERC20(address(0x0));

        _interInfo.blockTime = block.number;
    }



    function _addUser(address _user) private {
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





    function deposit(address tokenAddress, uint256 amount) payable external {
        _addUser(msg.sender);
        _updateInterest(msg.sender);

        require(amount > 0);
        require(tokenAddress == address(USDC_TOKEN) || tokenAddress == address(ETH_TOKEN));

        if(tokenAddress == address(ETH_TOKEN)) {
            require(0 < msg.value);
            require(amount <= msg.value);

            ledgers[msg.sender].ETH_collateral += amount;

        } else { // USDC TOKEN
            require(USDC_TOKEN.allowance(msg.sender, address(this)) >= amount);
            ledgers[msg.sender].USDC_balance += amount;
            USDC_TOTAL_DEPOSIT += amount;

            USDC_TOKEN.transferFrom(msg.sender, address(this), amount);
        }

        emit Deposit(msg.sender, tokenAddress, amount);
    }



    function borrow(address tokenAddress, uint256 amount) payable external {
        _updateInterest(msg.sender);
        _addUser(msg.sender);

        require(tokenAddress == address(USDC_TOKEN));
        require(0 < amount);
        require(amount <= USDC_TOKEN.balanceOf(address(this)));


        uint256 USDC_collateral_LTV = ledgers[msg.sender].ETH_collateral * oracle.getPrice(address(ETH_TOKEN)) / oracle.getPrice(address(USDC_TOKEN)) * 50 / 100;
        uint256 USDC_debt = ledgers[msg.sender].USDC_debt ;


        require(amount + USDC_debt <= USDC_collateral_LTV );

        ledgers[msg.sender].USDC_debt += amount;
        ledgers[msg.sender].USDC_borrow_time = block.number;

        USDC_TOTAL_BORROW += amount;

        // 이자 설정
        _interInfo.USDC_total_debt += amount;
        _interInfo.blockTime = block.number;

        USDC_TOKEN.transfer(msg.sender, amount);

        emit Borrow(msg.sender, amount);
    }


    // repay(address tokenAddress, uint256 amount)
    // DESC: 상환을 위한 함수
    // arg[0]: 상환하고자 하는 토큰의 주소
    // arg[1]: 상환금액
    // TODO: 이자율 고려해야 하는 것으로 보임
    function repay(address tokenAddress, uint256 amount) external {
        _addUser(msg.sender);
        _updateInterest(msg.sender);

        
        require(tokenAddress == address(USDC_TOKEN), "1");
        require(amount > 0 , "2");
        require(USDC_TOKEN.allowance(msg.sender, address(this)) >= amount, "3");
        
        USDC_TOKEN.transferFrom(msg.sender, address(this), amount);

        _interInfo.USDC_total_debt -= amount;
        ledgers[msg.sender].USDC_debt -= amount;

        emit Repay(msg.sender, amount);
    }



    // liquidate(address user, address tokenAddress, uint256 amount)
    // DESC: 강제 청산을 진행하는 함수 청산을 요구한 사람이 담보에 해당하는 만큼의 금액을 가져갈 수 있으며 제공한 비용은 프로토콜에서
    //       가져갈 수 있도록 한다.
    // arg[0]: 고객
    // arg[1]: 토큰의 종류
    // arg[2]: 청산하고자 하는 양
    function liquidate(address user, address tokenAddress, uint256 amount) external {
        require(tokenAddress == address(USDC_TOKEN));
        _addUser(msg.sender);
        _updateInterest(msg.sender);

        uint256 debt_collateral_ratio = ledgers[user].USDC_debt * 100 * 1e18 
                                        / (ledgers[user].ETH_collateral * oracle.getPrice(address(ETH_TOKEN)) 
                                        / oracle.getPrice(address(USDC_TOKEN)));

        // [1] 담보가치가 75% 이상 여부에 대한 검증 
        require(debt_collateral_ratio >= 75 * 1e18, "liquidation hold is 75");

        // [2] 빚이 100 ether 초과하는 경우 한번에 1/4만 청산가능하다.
        if(ledgers[user].USDC_debt > 100 ether) {
            require(amount * 4 <= ledgers[user].USDC_debt);
        } 

        // [3] 실제 청산을 통해 빚을 차감해주고 청산을 진행한 자가 갚아준 빚의 비율만큼 담보를 획득
        require(amount <= USDC_TOKEN.allowance(msg.sender, address(this)));
        require(amount <= USDC_TOKEN.balanceOf(msg.sender));
        require(ledgers[user].USDC_debt > 0);

        ledgers[user].USDC_debt -= amount;
        _interInfo.USDC_total_debt -= amount;
        
        uint256 ETH_ratio = amount * ledgers[user].ETH_collateral / ledgers[user].USDC_debt;
        
        USDC_TOKEN.transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(ETH_ratio);

        emit Liquidate(msg.sender, user, amount);
    }

    

    // withdraw(address tokenAddress, uint256 amount)
    // DESC: 금액을 인출하는 함수, 단 이자율을 고려해야 한다.
    // arg[0]: 인출하고자 하는 토큰
    // arg[1]: 인출하고자 하는 금액
    function withdraw(address tokenAddress, uint256 amount) payable external {
        _addUser(msg.sender);
        _updateInterest(msg.sender);


        require(0 < amount);
        require(tokenAddress == address(USDC_TOKEN) || tokenAddress == address(ETH_TOKEN));

        if(tokenAddress == address(ETH_TOKEN)) {
            if(ledgers[msg.sender].USDC_debt != 0) { // 빚이 존재할 경우 환산해보자
                require(ledgers[msg.sender].USDC_debt * oracle.getPrice(address(USDC_TOKEN)) / oracle.getPrice(address(ETH_TOKEN)) * 1e28 
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

        emit Withdraw(msg.sender, tokenAddress, amount);
    }


    function getAccruedSupplyAmount(address token) external returns (uint256) {
        _updateInterest(msg.sender);
        
        return ledgers[msg.sender].USDC_balance;    
    }


    function _updateInterest(address _user) private {
        uint256 _blockPeriod = block.number - _interInfo.blockTime;


        if(_blockPeriod > 0) {
            uint256 interestAfter = _calculate(_interInfo.USDC_total_debt, _blockPeriod) / 10 ** 9;
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
    }




    function _calculateUserInterest(uint256 amount, address _user) private {
        for(uint256 i=0; i<users.length; i++) {
            uint256 user_interest = amount * 1e24 * ledgers[users[i]].USDC_balance / USDC_TOTAL_DEPOSIT ;
            ledgers[users[i]].USDC_balance = (ledgers[users[i]].USDC_balance * 1e24 + user_interest) / 1e24 ;
        }
    }



    function _calculate(uint256 _amountUSDC, uint256 _blockPeriod) internal returns(uint256) {
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