// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../src/SimpleGamblingMachine.sol";

contract SimpleGamblingMachineTest is Test {
    SimpleGamblingMachine public machine;

    // Add receive function to accept ETH
    receive() external payable {}

    function setUp() public {
        // Fund this test contract
        vm.deal(address(this), 1 ether);
        // Deploy the game with the required initial balance
        machine = new SimpleGamblingMachine{value: 0.01 ether}();
    }

    function testInitialBalance() public {
        assertEq(address(machine).balance, 0.01 ether);
    }

    function testDeposit() public {
        uint256 required = machine.nextRequiredDeposit();
        vm.deal(address(this), required);
        machine.deposit{value: required}();

        assertEq(machine.depositCount(), 1);
        assertEq(machine.lastDepositor(), address(this));
    }

    function testRevertsOnWrongAmount() public {
        vm.expectRevert("Wrong deposit amount");
        machine.deposit{value: 0.001 ether}();
    }

    function testClaimFailsBeforeTimeout() public {
        uint256 required = machine.nextRequiredDeposit();
        vm.deal(address(this), required);
        machine.deposit{value: required}();

        vm.expectRevert("Still within timeout");
        machine.claimTimeout();
    }

    function testClaimTimeout() public {
        uint256 required = machine.nextRequiredDeposit();
        vm.deal(address(this), required);
        machine.deposit{value: required}();

        // Top-up contract so there's enough for payout
        vm.deal(address(machine), 2 ether);

        // Advance time past the first timeout (24h)
        skip(24 hours + 1);
        machine.claimTimeout();

        assertEq(machine.depositCount(), 0);
        assertEq(machine.lastDepositor(), address(0));
    }
}
