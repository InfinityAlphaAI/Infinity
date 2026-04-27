// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";
import {IPancakeFactory} from "./interfaces/IPancakeFactory.sol";
import {IDistributor} from "./interfaces/IDistributor.sol";
import {IPancakePair} from "./interfaces/IPancakePair.sol";

uint256 constant LP_MIN_BALANCE = 88888 * 1e18;
uint256 constant MIN_TOTAL_SUPPLY = 9999999 * 1e18;

contract Token is ERC20, Ownable, ERC20Burnable {
    address public router;
    address public pair;
    address public feeRobot;
    address public interaction;
    address public operator;
    address public cashToken;
    address public burnReceiver;
    bool public isOpenBuy;
    mapping(address => bool) public isGuardedOf;

    event Guarded(address indexed user, uint256 indexed time, bool addOrRemove);

    constructor(
        address _router,
        address _cashToken,
        address _operator
    ) ERC20("Infinity Alpha", "IA") {
        _mint(msg.sender, 88888888 * 1e18);
        router = _router;
        cashToken = _cashToken;
        burnReceiver = _operator;
        pair = IPancakeFactory(IPancakeRouter(router).factory()).createPair(
            address(this),
            _cashToken
        );
        operator = _operator;
    }

    function setAddress(
        address _feeRobot,
        address _interaction
    ) external onlyOwner {
        feeRobot = _feeRobot;
        interaction = _interaction;
        isGuardedOf[interaction] = true;
        isGuardedOf[feeRobot] = true;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "not operator");
        _;
    }

    function openBuy() external onlyOperator {
        isOpenBuy = true;
    }

    function setBurnReceiver(address _burnReceiver) external onlyOperator {
        require(_burnReceiver != address(0), "invalid burn receiver");
        burnReceiver = _burnReceiver;
    }

    function transferOperator(address newOperator) external onlyOperator {
        operator = newOperator;
    }

    function addGuarded(address account) external onlyOperator {
        require(!isGuardedOf[account], "account already exist");
        isGuardedOf[account] = true;
        emit Guarded(account, block.timestamp, true);
    }

    function removeGuarded(address account) external onlyOperator {
        require(isGuardedOf[account], "account not exist");
        isGuardedOf[account] = false;
        emit Guarded(account, block.timestamp, false);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        uint256 feeAmount;
        if (!isGuardedOf[from] && !isGuardedOf[to]) {
            if (from == pair) {
                require(isOpenBuy, "buy not open");
            }
            if (to == pair) {
                _burn(pair, amount / 2);
                IPancakePair(pair).sync();

                feeAmount = amount / 2;
                super._transfer(from, feeRobot, feeAmount);
                IDistributor(feeRobot).distribute();
            }
        }
        super._transfer(from, to, amount - feeAmount);
    }

    function _min3(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return a < b ? (a < c ? a : c) : (b < c ? b : c);
    }

    function _burn(address from, uint256 amount) internal override {
        uint256 lpBalance = balanceOf(pair);
        uint256 totalSupply = totalSupply();
        uint256 a = amount;
        uint256 b = 0;
        uint256 c = 0;

        if (from == pair) {
            if (lpBalance > LP_MIN_BALANCE) {
                b = lpBalance - LP_MIN_BALANCE;
            }
        } else {
            b = amount;
        }

        if (totalSupply > MIN_TOTAL_SUPPLY) {
            c = totalSupply - MIN_TOTAL_SUPPLY;
        }
        uint256 burnAmount = _min3(a, b, c);
        if (burnAmount > 0) {
            super._burn(from, burnAmount);
        }
        if (amount - burnAmount > 0) {
            super._transfer(from, burnReceiver, amount - burnAmount);
        }
    }

    function reSync(uint256 amount, address to) external {
        require(msg.sender == interaction, "can not burn token from pair");
        super._transfer(pair, to, amount);
        IPancakePair(pair).sync();
    }
}
