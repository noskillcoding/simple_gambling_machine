// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SimpleGamblingMachine is ReentrancyGuard {
    // —————— PARAMETER CONSTANTS ——————
    uint256 public constant INITIAL_BALANCE = 0.01 ether;
    uint16 public constant WINNER_BPS = 8000;  // 80% to last depositor
    uint16 public constant RANDOM_TOTAL_BPS = 1000; // 10% split among randoms

    uint16[] public depositBps = [200, 150, 120, 100, 50, 20]; // Deposit tiers: 2%, 1.5%, ... 0.2%
    uint[] public depositLimits = [50, 125, 225, 425, 925];    // Cumulative deposit thresholds

    uint256[] public timeoutSecs = [24 hours, 16 hours, 12 hours, 6 hours, 3 hours, 1 hours];

    // —————— STATE VARIABLES ——————
    uint256 public depositCount;
    address public lastDepositor;
    uint256 public lastDepositTime;

    address[] public depositors;

    // —————— EVENTS ——————
    event DepositMade(address indexed depositor, uint256 amount, uint16 bps);
    event GameWon(address indexed winner, uint256 prizeAmount);
    event RandomReward(address indexed recipient, uint256 amount);

    // —————— CONSTRUCTOR ——————
    constructor() payable {
        require(msg.value == INITIAL_BALANCE, "Must fund with 0.01 ETH");
        lastDepositTime = block.timestamp;
    }

    // —————— PUBLIC FUNCTIONS ——————

    function deposit() external payable nonReentrant {
        uint16 bps = _currentDepositBps();
        uint256 before = address(this).balance - msg.value;
        uint256 required = (before * bps) / 10_000;
        require(msg.value == required, "Wrong deposit amount");

        depositCount++;
        lastDepositor = msg.sender;
        lastDepositTime = block.timestamp;
        depositors.push(msg.sender);

        emit DepositMade(msg.sender, msg.value, bps);
    }

    function claimTimeout() external nonReentrant {
        uint256 period = _currentTimeout();
        require(block.timestamp >= lastDepositTime + period, "Still within timeout");

        uint256 balance = address(this).balance;
        uint256 winnerAmount = (balance * WINNER_BPS) / 10_000;
        uint256 totalRandom = (balance * RANDOM_TOTAL_BPS) / 10_000;
        uint256 eachRandom = totalRandom / 5;

        (bool success, ) = lastDepositor.call{value: winnerAmount}("");
        require(success, "Winner transfer failed");
        emit GameWon(lastDepositor, winnerAmount);

        for (uint i = 0; i < 5 && i < depositors.length; i++) {
            address randomAddr = depositors[_randomIndex(i) % depositors.length];
            (bool sent, ) = randomAddr.call{value: eachRandom}("");
            if (sent) emit RandomReward(randomAddr, eachRandom);
        }

        // Reset game
        depositCount = 0;
        lastDepositor = address(0);
        lastDepositTime = block.timestamp;
        delete depositors;
    }

    function nextRequiredDeposit() public view returns (uint256) {
        if (address(this).balance == 0) return 0;
        uint16 bps = _currentDepositBps();
        return (address(this).balance * bps) / 10_000;
    }

    // —————— INTERNAL HELPERS ——————

    function _currentDepositBps() internal view returns (uint16) {
        uint256 cnt = depositCount;
        for (uint i = 0; i < depositLimits.length; i++) {
            if (cnt < depositLimits[i]) return depositBps[i];
        }
        return depositBps[depositBps.length - 1];
    }

    function _currentTimeout() internal view returns (uint256) {
        uint256 cnt = depositCount;
        if (cnt < depositLimits[0]) return timeoutSecs[0];
        else if (cnt < depositLimits[1]) return timeoutSecs[1];
        else if (cnt < depositLimits[2]) return timeoutSecs[2];
        else if (cnt < depositLimits[3]) return timeoutSecs[3];
        else if (cnt < depositLimits[4]) return timeoutSecs[4];
        else return timeoutSecs[5];
    }

    function _randomIndex(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, seed, blockhash(block.number - 1))));
    }

    receive() external payable {}
}
