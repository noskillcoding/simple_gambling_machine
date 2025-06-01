// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../src/SimpleGamblingMachine.sol"; // Ensure this path is correct

contract SimpleGamblingMachineTest is Test {
    SimpleGamblingMachine public machine;
    address payable public user1;
    address payable public user2;
    address payable public user3;
    address payable public user4;
    address payable public user5;

    receive() external payable {}

    function setUp() public {
        user1 = payable(address(uint160(bytes20(keccak256(abi.encodePacked("user1"))))));
        user2 = payable(address(uint160(bytes20(keccak256(abi.encodePacked("user2"))))));
        user3 = payable(address(uint160(bytes20(keccak256(abi.encodePacked("user3"))))));
        user4 = payable(address(uint160(bytes20(keccak256(abi.encodePacked("user4"))))));
        user5 = payable(address(uint160(bytes20(keccak256(abi.encodePacked("user5"))))));

        vm.deal(address(this), 5 ether);

        // Use 0.001 ether to match the contract's INITIAL_BALANCE
        uint256 initialFundingValue = 0.001 ether;
        machine = new SimpleGamblingMachine{value: initialFundingValue}();

        assertEq(address(machine).balance, machine.INITIAL_BALANCE());
    }

    function testInitialBalance() public {
        assertEq(address(machine).balance, machine.INITIAL_BALANCE());
        assertEq(machine.depositCount(), 0);
    }

    function _makeDeposits(uint256 numDeposits) private {
        address payable[5] memory users; // <<<< CORRECTED LINE
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = user4;
        users[4] = user5;

        for (uint256 i = 0; i < numDeposits; ++i) {
            address depositor = users[i % 5];
            vm.startPrank(depositor);

            uint256 required = machine.nextRequiredDeposit();
            if (required == 0 && address(machine).balance > 0) {
                vm.deal(address(machine), address(machine).balance + 0.001 ether);
                required = machine.nextRequiredDeposit();
            }
            require(required > 0, "Test setup: required deposit is 0, cannot proceed.");

            vm.deal(depositor, required + 0.1 ether);
            machine.deposit{value: required}();
            vm.stopPrank();
        }
    }

    function testDeposit() public {
        vm.deal(address(this), 1 ether); // Ensure test contract has ETH to send
        uint256 initialDepositCount = machine.depositCount();
        uint256 required = machine.nextRequiredDeposit();

        // If the initial balance is exactly what nextRequiredDeposit needs for its calculation basis,
        // and nextRequiredDeposit returns 0 (e.g., due to very low contract balance),
        // a deposit of 0 would still be valid.
        // However, with INITIAL_BALANCE = 0.001 ether and depositBps[0] = 200 (2%),
        // required should be (0.001 ether * 200) / 10000 = 0.00002 ether.
        // So, ensure `required` makes sense in the context of the test.
        if (required == 0 && address(machine).balance > 0) {
             // This case might indicate an issue or an edge case worth investigating
             // For a typical first deposit after setup, 'required' should be > 0.
             // We might need to add funds to the depositor if required is 0,
             // or the test might assume 'required' > 0.
             // For this simple deposit test, let's assume 'required' will be positive.
        } else if (required == 0 && address(machine).balance == 0) {
            // If contract balance is 0, required is 0, deposit of 0 is allowed.
             machine.deposit{value: 0}();
        } else {
             machine.deposit{value: required}();
        }

        assertEq(machine.depositCount(), initialDepositCount + 1);
        assertEq(machine.lastDepositor(), address(this));
    }

    function testRevertsOnWrongAmount() public {
        vm.deal(address(this), 1 ether); // Ensure test contract has ETH
        uint256 required = machine.nextRequiredDeposit();

        if (required > 0) {
            // Sending less than 'required' should revert
            uint256 tooLittle = required - 1;
            vm.expectRevert(bytes("Wrong deposit amount")); // Use bytes() for string literals in expectRevert
            machine.deposit{value: tooLittle}();
        } else {
            // If required == 0, then sending any positive value (msg.value > required)
            // will mean `dust = msg.value - 0 = msg.value`.
            // The deposit itself still happens, required (0) is kept, dust is refunded.
            uint256 beforeCount = machine.depositCount();
            machine.deposit{value: 1 wei}(); // Send 1 wei as dust
            assertEq(machine.depositCount(), beforeCount + 1);
            assertEq(machine.lastDepositor(), address(this));
            // Check if 1 wei was refunded (this.balance should not decrease by 1 wei if it had funds)
        }
    }

    function testClaimFailsBeforeTimeout() public {
        vm.startPrank(user1);
        uint256 required = machine.nextRequiredDeposit();
        vm.deal(user1, required + 0.1 ether); // Deal enough for deposit
        machine.deposit{value: required}();
        vm.stopPrank();

        vm.expectRevert(bytes("Still within timeout")); // Use bytes()
        machine.claimTimeout();
    }

    function testClaimTimeout_BasicFunctionality() public {
        vm.startPrank(user1);
        uint256 requiredOnFirstDeposit = machine.nextRequiredDeposit();
        vm.deal(user1, requiredOnFirstDeposit + 1 ether); // user1 has enough ETH
        machine.deposit{value: requiredOnFirstDeposit}();
        vm.stopPrank();

        // At this point, only user1 has deposited.
        // For random rewards, if depositCount (filled) is 1,
        // _randomIndex(i) % 1 will always be 0.
        // So, user1 will be chosen for all 5 "random" rewards if eligible.

        uint256 fundsForPayout = 2 ether; // Add more funds to the contract to make payouts substantial
        vm.deal(address(machine), address(machine).balance + fundsForPayout);
        uint256 balanceBeforeClaim = address(machine).balance;

        uint256 timeout = machine._currentTimeout(); // Get current timeout based on depositCount
        skip(timeout + 1); // Skip just past the timeout

        uint256 winnerInitialEth = user1.balance;

        // Expected events
        // Winner (user1)
        uint256 expectedWinnerAmount = (balanceBeforeClaim * machine.WINNER_BPS()) / 10000;
        vm.expectEmit(true, true, true, true);
        emit SimpleGamblingMachine.GameWon(user1, expectedWinnerAmount);

        // Random rewards (user1 will get all of them as it's the only depositor)
        uint256 totalRandomAmountPool = (balanceBeforeClaim * machine.RANDOM_TOTAL_BPS()) / 10000;
        uint256 eachRandomAmount = totalRandomAmountPool / 5;

        // Since depositCount is 1, `filled` will be 1.
        // The loop runs for `i = 0; i < 5 && i < 1; i++`, so it runs only for i=0.
        // Only one random reward will actually be paid out.
        if (eachRandomAmount > 0 && machine.depositCount() > 0) { // depositCount is 1 here
             vm.expectEmit(true, true, true, true);
             emit SimpleGamblingMachine.RandomReward(user1, eachRandomAmount);
        }


        machine.claimTimeout();

        assertEq(machine.depositCount(), 0, "Deposit count should reset");
        assertEq(machine.lastDepositor(), address(0), "Last depositor should reset");

        uint256 expectedGainForUser1;
        uint256 totalActuallyPaidToRandom = 0;

        if (machine.RANDOM_TOTAL_BPS() > 0 && machine.WINNER_BPS() < 10000) { // Check if random rewards are active
            // With only 1 depositor (user1), they get the winner prize AND the first random prize.
            // The loop for random rewards: for (uint256 i = 0; i < 5 && i < filled; i++)
            // If filled (depositCount before reset) was 1, loop runs once for i=0.
            // randIdx = _randomIndex(0) % 1 = 0. So depositors[0] (user1) gets this one random reward.
             if (eachRandomAmount > 0) {
                totalActuallyPaidToRandom = eachRandomAmount; // Only one random reward paid
             }
        }
        expectedGainForUser1 = expectedWinnerAmount + totalActuallyPaidToRandom;


        assertEq(
            user1.balance,
            winnerInitialEth + expectedGainForUser1,
            "Winner (user1) payout incorrect"
        );

        uint256 totalPaidOut = expectedWinnerAmount + totalActuallyPaidToRandom;
        assertEq(
            address(machine).balance,
            balanceBeforeClaim - totalPaidOut,
            "Contract balance after claim incorrect"
        );
    }


    function testHiddenHouseEdge() public {
        // Deal ETH to users so they can deposit
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);
        vm.deal(user4, 1 ether);
        vm.deal(user5, 1 ether);

        _makeDeposits(5); // user1, user2, user3, user4, user5 deposit

        // Now user5 is the lastDepositor
        // depositCount is 5

        // Set a specific balance for the machine to test truncation precisely
        // Choose a balance that might cause truncation in payouts.
        // Example: a balance that isn't perfectly divisible by 10000 or by 5 for random shares.
        uint256 balanceForPayout = 0.12345 ether; // A value likely to cause truncation
        vm.deal(address(machine), balanceForPayout); // This sets the balance exactly
        // Note: _makeDeposits adds to the balance. If we want an exact balance *after* deposits,
        // we should calculate the sum of deposits and then vm.deal the *difference* to reach balanceForPayout,
        // or simply overwrite the balance like this if _makeDeposits already ran and we want a fresh specific balance.
        // For simplicity here, we're setting it directly after deposits. This means the deposits' value
        // is part of this `balanceForPayout` if it was set higher than sum of deposits + initial.
        // Let's ensure it's higher than initial balance for clarity.
        if (balanceForPayout <= machine.INITIAL_BALANCE()) {
            balanceForPayout = machine.INITIAL_BALANCE() + 0.1 ether; // Ensure it's a reasonable amount
        }
        vm.deal(address(machine), 0); // Zero out balance
        vm.deal(address(machine), balanceForPayout); // Set exact balance for test predictability
        assertEq(address(machine).balance, balanceForPayout, "Failed to set specific balance for test");


        uint256 timeout = machine._currentTimeout(); // Timeout for 5 deposits
        skip(timeout + 1);

        // Store balances before claimTimeout
        uint256 user5BalanceBefore = user5.balance; // user5 is the winner
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;
        uint256 user3BalanceBefore = user3.balance;
        uint256 user4BalanceBefore = user4.balance;


        machine.claimTimeout(); // user5 (last depositor) calls this or any other address

        uint256 winnerPayout = (balanceForPayout * machine.WINNER_BPS()) / 10000;
        uint256 totalRandomPayoutPool = (balanceForPayout * machine.RANDOM_TOTAL_BPS()) / 10000;
        uint256 eachRandomPayout = totalRandomPayoutPool / 5; // Solidity integer division

        uint256 totalPaidToPlayers = winnerPayout;
        // In claimTimeout, random rewards are paid from depositors array.
        // With 5 deposits, 'filled' is 5. Loop runs 5 times.
        // We need to check which users got the random rewards.
        // For this test, we are more interested in total payout vs house retention.
        // The contract pays up to 5 randoms. If less than 5 unique randoms are chosen from 5 depositors,
        // or if a depositor is chosen multiple times, they'd get multiple `eachRandomPayout`.
        // However, the loop `for (uint256 i = 0; i < 5 && i < filled; i++)` implies 5 attempts.
        // `_randomIndex(i)` will produce different indices (potentially).
        // The most straightforward is to assume 5 * eachRandomPayout if RANDOM_TOTAL_BPS > 0
        // and filled >= 5.
        if (machine.RANDOM_TOTAL_BPS() > 0) {
            totalPaidToPlayers += (5 * eachRandomPayout);
        }


        uint256 actualHouseRetention = address(machine).balance;
        // The expected house retention based on actual payouts
        uint256 expectedHouseRetentionAfterPayouts = balanceForPayout - totalPaidToPlayers;

        assertEq(
            actualHouseRetention,
            expectedHouseRetentionAfterPayouts,
            "Actual house retention calculation mismatch with total player payouts"
        );

        uint256 nominalHouseBps = 10000 - machine.WINNER_BPS() - machine.RANDOM_TOTAL_BPS();
        uint256 calculatedNominalHouseCut = (balanceForPayout * nominalHouseBps) / 10000; // Solidity integer division

        // Check for truncation conditions
        bool winnerWasTruncated = (balanceForPayout * machine.WINNER_BPS()) % 10000 != 0;
        bool randomTotalWasTruncated = (balanceForPayout * machine.RANDOM_TOTAL_BPS()) % 10000 != 0;
        // eachRandomWasTruncated if totalRandomPayoutPool was not perfectly divisible by 5
        bool eachRandomWasTruncated = (machine.RANDOM_TOTAL_BPS() > 0) && (totalRandomPayoutPool % 5 != 0);

        if (winnerWasTruncated || randomTotalWasTruncated || eachRandomWasTruncated) {
            // If any part of player payout was truncated, house keeps that truncated dust.
            // So actual retention should be >= nominal cut. It will be > if truncation occurred.
            assertGe( // Greater than or equal because nominal cut itself is floored.
                     // If only nominal cut was truncated but player payouts were not, actual could equal nominal.
                     // The critical part is if player payouts are truncated, house gets more.
                actualHouseRetention,
                calculatedNominalHouseCut,
                "Hidden house edge: Actual retention should be >= nominal due to truncation."
            );
            // To be more precise: if player payouts are truncated, actualHouseRetention should be
            // calculatedNominalHouseCut + sum_of_truncations_from_player_payouts.
            // The test aims to show that actual retention can be *greater* than the naive nominal calculation.
            if (actualHouseRetention > calculatedNominalHouseCut) {
                emit log_string("Hidden house edge confirmed due to player payout truncation or nominal cut truncation:");
                emit log_named_uint("  Balance For Payout", balanceForPayout);
                emit log_named_uint("  Actual House Retention", actualHouseRetention);
                emit log_named_uint("  Calculated Nominal House Cut (Floored)", calculatedNominalHouseCut);
                emit log_named_uint("  Winner Payout (Floored)", winnerPayout);
                emit log_named_uint("  Total Random Pool (Floored)", totalRandomPayoutPool);
                emit log_named_uint("  Each Random (Floored)", eachRandomPayout);
                emit log_named_uint("  Total Player Payouts (Sum of Floored Vals)", totalPaidToPlayers);
            } else {
                // This case could happen if nominal cut truncation equals player payout truncations.
                emit log_string("No strict hidden house edge from player payout truncation vs nominal for this balance, or effects cancelled out:");
                 emit log_named_uint("  Actual House Retention", actualHouseRetention);
                emit log_named_uint("  Calculated Nominal House Cut (Floored)", calculatedNominalHouseCut);
            }
        } else {
            // If no truncation occurred in player payouts AND no truncation in nominal house cut calc
            assertEq(
                actualHouseRetention,
                calculatedNominalHouseCut,
                "House edge should be exactly nominal if no truncation occurred anywhere."
            );
            emit log_string("No hidden house edge from truncation for this specific balance:");
            emit log_named_uint("  Balance For Payout", balanceForPayout);
        }
    }


    function testRequiredDepositBecomesZeroAndHandling() public {
        // Test with a balance so low that initial bps (2%) of it is less than 1 wei, thus 0.
        // INITIAL_BALANCE = 0.001 ether = 1_000_000_000_000_000 wei
        // depositBps[0] = 200 (2%)
        // required = (balance * 200) / 10000 = balance / 50
        // If balance < 50 wei, required will be 0.
        uint256 smallBalance = 49 wei;
        vm.deal(address(machine), 0); // Zero out initial balance from constructor
        vm.deal(address(machine), smallBalance); // Set the specific small balance

        assertEq(address(machine).balance, smallBalance);
        // depositCount is 0 from setUp, or rather, after contract deployment it's 0.
        // If new SimpleGamblingMachine was called in setUp, then it is 0.
        // Let's re-deploy for a clean state for this specific test, or ensure it's reset.
        // For simplicity, assuming it's a fresh state or depositCount is 0.
        // If testInitialBalance runs first, machine is already deployed.
        // Let's assume depositCount is 0. If not, this test needs its own machine instance or reset.
        // If machine's depositCount is NOT 0 from a previous test running in same context (not typical for Forge tests unless chained)
        // then _currentDepositBps might give a different bps.
        // Let's assume fresh state for depositCount = 0.
        assertEq(machine.depositCount(), 0, "Initial deposit count should be 0 for this test logic");


        uint256 required = machine.nextRequiredDeposit();
        assertEq(required, 0, "Required deposit should be 0 for balance of 49 wei and 0 deposits");

        address depositorForZeroValue = user3;
        vm.deal(depositorForZeroValue, 1 ether); // Give user some ETH
        vm.startPrank(depositorForZeroValue);
        uint256 depositCountBefore = machine.depositCount();
        uint256 lastDepositTimeBefore = machine.lastDepositTime();

        // A deposit of 0 is allowed if required is 0. No dust to refund.
        machine.deposit{value: 0}();

        assertEq(
            machine.depositCount(),
            depositCountBefore + 1,
            "Deposit count should increment for 0-value deposit when required is 0"
        );
        assertEq(
            machine.lastDepositor(),
            depositorForZeroValue,
            "Last depositor should be set for 0-value deposit"
        );
        assertTrue(
            machine.lastDepositTime() > lastDepositTimeBefore || // Time advanced
            (lastDepositTimeBefore == 0 && machine.lastDepositTime() > 0) || // Initial deposit time set
            block.timestamp == machine.lastDepositTime(), // Time is current block timestamp
            "Last deposit time should be updated"
        );
        vm.stopPrank();

        // After one deposit, depositCount is now 1.
        // _currentDepositBps will still be depositBps[0] (2%) as 1 < depositLimits[0] (50).
        // Contract balance is still 49 wei (0 was added).
        // So, nextRequiredDeposit should still be (49 wei * 200) / 10000 = 0.
        required = machine.nextRequiredDeposit();
        assertEq(required, 0, "Required deposit should still be 0 after one 0-value deposit if balance unchanged");

        // Now, if required is 0, msg.value must be >= required (so >=0).
        // If we send value: 1 wei. required is 0. dust = 1 - 0 = 1 wei.
        // The deposit logic: require(msg.value >= required) passes.
        // Dust of 1 wei is refunded. Deposit still happens.
        // The original test had:
        // "// After depositCount > 0, required > 0. Now sending 1 wei should revert."
        // This premise is only true if the balance increased such that required > 0.
        // With current balance 49 wei, required remains 0.
        // A deposit of 1 wei will succeed, and 1 wei will be refunded as dust.
        // To make it revert with "Wrong deposit amount", `required` must become > `msg.value`.
        // Let's adjust the contract balance so `required` becomes > 0.
        vm.deal(address(machine), 1000 wei); // Now balance is 1000 wei. depositCount is 1.
        // required = (1000 * 200) / 10000 = 20 wei.
        required = machine.nextRequiredDeposit();
        assertTrue(required > 0, "Required should now be positive after increasing balance.");

        vm.deal(user4, 1 ether); // Give user some ETH
        vm.startPrank(user4);
        vm.expectRevert(bytes("Wrong deposit amount"));
        machine.deposit{value: required - 1}(); // Send less than new required
        vm.stopPrank();


        // Test case: contract balance becomes 0.
        vm.deal(address(machine), 0 wei);
        assertEq(address(machine).balance, 0);
        required = machine.nextRequiredDeposit();
        assertEq(required, 0, "Required deposit should be 0 for 0 contract balance");

        address anotherDepositor = user4; // user4 already has ETH from above
        vm.startPrank(anotherDepositor);
        depositCountBefore = machine.depositCount(); // depositCount is 1 from previous successful 0-deposit
        machine.deposit{value: 0}(); // This should succeed as required is 0
        assertEq(
            machine.depositCount(),
            depositCountBefore + 1,
            "Deposit count should increment again for 0-value deposit on 0 balance"
        );
        assertEq(machine.lastDepositor(), anotherDepositor);
        vm.stopPrank();
    }
}