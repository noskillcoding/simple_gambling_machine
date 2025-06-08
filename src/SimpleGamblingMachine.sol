// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SimpleGamblingMachine is ReentrancyGuard {
    // —————— PARAMETER CONSTANTS ——————
    uint256 public constant INITIAL_BALANCE = 0.2 ether;
    uint16 public constant WINNER_BPS      = 8000; // 80 % to last depositor
    uint16 public constant RANDOM_TOTAL_BPS = 1000; // 10 % split among randoms

    // New deposit percentages in basis points (100 bps = 1%)
    uint16[] public depositBps = [200, 150, 120, 100, 50, 20, 5];

    // New cumulative deposit counts for each tier
    uint[] public depositLimits = [50, 125, 225, 425, 925, 1925];
    // depositBps / depositLimits correspond to:
    //  2%    for first 50 deposits
    //  1.5%  for next 75 deposits  (up to 125)
    //  1.2%  for next 100 deposits (up to 225)
    //  1%    for next 200 deposits (up to 425)
    //  0.5%  for next 500 deposits (up to 925)
    //  0.2%  for next 1000 deposits(up to 1925)
    //  0.05% thereafter

    // New timeout periods for each deposit tier
    uint256[] public timeoutSecs = [
        24 hours,
        16 hours,
        12 hours,
        6 hours,
        3 hours,
        2 hours,
        1 hours
    ];

    // —————— CIRCULAR BUFFER SETUP ——————
    uint256 public constant MAX_ENTRIES = 5096;
    address[MAX_ENTRIES] public depositors;
    // `depositors` is a fixed-length array of 5096 slots.
    // We will write each deposit into one slot at index = (depositCount % MAX_ENTRIES).

    // —————— STATE VARIABLES ——————
    uint256 public depositCount;    // total deposits this round
    address public lastDepositor;
    uint256 public lastDepositTime;

    // —————— EVENTS ——————
    event DepositMade(address indexed depositor, uint256 amount, uint16 bps);
    event GameWon(address indexed winner, uint256 prizeAmount);
    event RandomReward(address indexed recipient, uint256 amount);

    // —————— CONSTRUCTOR ——————
    constructor() payable {
        require(msg.value == INITIAL_BALANCE, "Must fund with 0.2 ETH");
        lastDepositTime = block.timestamp;
    }

    // —————— PUBLIC FUNCTIONS ——————

    function deposit() external payable nonReentrant {
        uint16  bps      = _currentDepositBps();
        uint256 before   = address(this).balance - msg.value;
        uint256 required = (before * bps) / 10_000;

        // 1) Accept >= required, then refund any “dust”
        require(msg.value >= required, "Wrong deposit amount");
        uint256 dust = msg.value - required;
        if (dust > 0) {
            (bool refOK, ) = payable(msg.sender).call{ value: dust }("");
            require(refOK, "Dust refund failed");
        }

        // 2) Write to our circular buffer at index = depositCount % MAX_ENTRIES
        uint256 idx = depositCount % MAX_ENTRIES;
        depositors[idx] = msg.sender;

        // 3) Update core state
        depositCount++;
        lastDepositor   = msg.sender;
        lastDepositTime = block.timestamp;

        emit DepositMade(msg.sender, required, bps);
    }

    function claimTimeout() external nonReentrant {
        require(depositCount > 0, "No deposits made this round");
        uint256 period = _currentTimeout();
        require(
            block.timestamp >= lastDepositTime + period,
            "Still within timeout"
        );

        uint256 balance      = address(this).balance;
        uint256 winnerAmount = (balance * WINNER_BPS) / 10_000;
        uint256 totalRandom  = (balance * RANDOM_TOTAL_BPS) / 10_000;
        uint256 eachRandom   = totalRandom / 5;

        // 1) Pay the last depositor
        (bool okWinner, ) = lastDepositor.call{ value: winnerAmount }("");
        require(okWinner, "Winner transfer failed");
        emit GameWon(lastDepositor, winnerAmount);

        // 2) Determine how many valid entries are in the buffer this round:
        uint256 filled = depositCount < MAX_ENTRIES
            ? depositCount
            : MAX_ENTRIES;

        // 3) Pay up to 5 “random” depositors from that pool
        for (uint256 i = 0; i < 5 && i < filled; i++) {
            uint256 randIdx = _randomIndex(i) % filled;
            address randomAddr = depositors[randIdx];

            (bool okR, ) = randomAddr.call{ value: eachRandom, gas: 2300 }("");
            if (okR) {
                emit RandomReward(randomAddr, eachRandom);
            }
        }

        // 4) Reset for next round
        depositCount    = 0;
        lastDepositor   = address(0);
        lastDepositTime = block.timestamp;
    }

    function nextRequiredDeposit() public view returns (uint256) {
        if (address(this).balance == 0) {
            return 0;
        }
        uint16  bps = _currentDepositBps();
        return (address(this).balance * bps) / 10_000;
    }

    // —————— INTERNAL HELPERS ——————

    function _currentDepositBps() internal view returns (uint16) {
        uint256 cnt = depositCount;
        for (uint256 i = 0; i < depositLimits.length; i++) {
            if (cnt < depositLimits[i]) {
                return depositBps[i];
            }
        }
        return depositBps[depositBps.length - 1];
    }

    /**
     * @notice Determines the current timeout period based on the number of deposits.
     * @dev This function was refactored to loop through deposit limits for better maintainability.
     */
    function _currentTimeout() public view returns (uint256) {
        uint256 cnt = depositCount;
        for (uint256 i = 0; i < depositLimits.length; i++) {
            if (cnt < depositLimits[i]) {
                return timeoutSecs[i];
            }
        }
        return timeoutSecs[timeoutSecs.length - 1];
    }

    function _randomIndex(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        seed,
                        blockhash(block.number - 1)
                    )
                )
            );
    }

    receive() external payable {}
}