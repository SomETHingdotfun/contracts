// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SomeTimelock} from "contracts/SomeTimelock.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";

import "forge-std/console.sol";

/// @title MockTarget
/// @notice Mock contract for testing timelock operations
contract MockTarget {
  uint256 public value;
  string public message;

  event ValueSet(uint256 newValue);
  event MessageSet(string newMessage);

  function setValue(uint256 _value) external {
    value = _value;
    emit ValueSet(_value);
  }

  function setMessage(string calldata _message) external {
    message = _message;
    emit MessageSet(_message);
  }

  function revertFunction() external pure {
    revert("MockTarget: intentional revert");
  }

  function payableFunction() external payable {
    // Accept ETH
  }
}

contract SomeTimelockTest is Test {
  SomeTimelock timelock;
  MockTarget target;

  address admin;
  address proposer1;
  address proposer2;
  address executor1;
  address executor2;
  address user1;
  address user2;

  uint256 constant MIN_DELAY = 3600; // 1 hour

  bytes32 constant ADMIN_ROLE = 0x00; // DEFAULT_ADMIN_ROLE
  bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
  bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

  event CallScheduled(
    bytes32 indexed id,
    uint256 indexed index,
    address target,
    uint256 value,
    bytes data,
    bytes32 predecessor,
    uint256 delay
  );

  event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);
  event Cancelled(bytes32 indexed id);

  function setUp() public {
    admin = makeAddr("admin");
    proposer1 = makeAddr("proposer1");
    proposer2 = makeAddr("proposer2");
    executor1 = makeAddr("executor1");
    executor2 = makeAddr("executor2");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");

    // Create proposers array
    address[] memory proposers = new address[](2);
    proposers[0] = proposer1;
    proposers[1] = proposer2;

    // Deploy timelock
    vm.prank(admin);
    timelock = new SomeTimelock(MIN_DELAY, admin, proposers);

    // Deploy mock target
    target = new MockTarget();

    // Label addresses for better debugging
    vm.label(address(timelock), "timelock");
    vm.label(address(target), "target");
    vm.label(admin, "admin");
    vm.label(proposer1, "proposer1");
    vm.label(proposer2, "proposer2");
    vm.label(executor1, "executor1");
    vm.label(executor2, "executor2");
    vm.label(user1, "user1");
    vm.label(user2, "user2");
  }

  function test_constructor_initialization() public {
    assertEq(timelock.getMinDelay(), MIN_DELAY);
    assertTrue(timelock.hasRole(ADMIN_ROLE, admin));
    assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer1));
    assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer2));
    assertTrue(timelock.hasRole(EXECUTOR_ROLE, proposer1)); // proposers are also executors
    assertTrue(timelock.hasRole(EXECUTOR_ROLE, proposer2));
    assertTrue(timelock.hasRole(CANCELLER_ROLE, proposer1));
    assertTrue(timelock.hasRole(CANCELLER_ROLE, proposer2));
  }

  function test_role_enumeration() public {
    // Test getAllProposers
    address[] memory proposers = timelock.getAllProposers();
    assertEq(proposers.length, 2);
    // Order may vary, so just check that both are present
    assertTrue(proposers[0] == proposer1 || proposers[0] == proposer2);
    assertTrue(proposers[1] == proposer1 || proposers[1] == proposer2);

    // Test getAllExecutors (proposers are also executors)
    address[] memory executors = timelock.getAllExecutors();
    assertEq(executors.length, 2);
    // Order may vary, so just check that both are present
    assertTrue(executors[0] == proposer1 || executors[0] == proposer2);
    assertTrue(executors[1] == proposer1 || executors[1] == proposer2);

    // Test getAllAdmins - the count may vary depending on OpenZeppelin implementation
    address[] memory admins = timelock.getAllAdmins();
    assertTrue(admins.length >= 1);
    // Check that admin is in the list
    bool adminFound = false;
    for (uint256 i = 0; i < admins.length; i++) {
      if (admins[i] == admin) {
        adminFound = true;
        break;
      }
    }
    assertTrue(adminFound);

    // Test getAllCancellers (proposers are also cancellers)
    address[] memory cancellers = timelock.getAllCancellers();
    assertEq(cancellers.length, 2);
    // Order may vary, so just check that both are present
    assertTrue(cancellers[0] == proposer1 || cancellers[0] == proposer2);
    assertTrue(cancellers[1] == proposer1 || cancellers[1] == proposer2);
  }

  function test_schedule_and_execute_simple_call() public {
    uint256 newValue = 42;
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, newValue);

    // Schedule the call
    vm.startPrank(proposer1);
    bytes32 operationId = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Verify the operation is scheduled
    assertTrue(timelock.isOperation(operationId));
    assertTrue(timelock.isOperationPending(operationId));
    assertFalse(timelock.isOperationReady(operationId));
    assertFalse(timelock.isOperationDone(operationId));

    // Fast forward time to make operation ready
    vm.warp(block.timestamp + MIN_DELAY + 1);

    // Verify operation is ready
    assertTrue(timelock.isOperationReady(operationId));

    // Execute the call
    vm.startPrank(proposer1);
    timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    vm.stopPrank();

    // Verify execution
    assertTrue(timelock.isOperationDone(operationId));
    assertEq(target.value(), newValue);
  }

  function test_schedule_and_execute_with_eth() public {
    uint256 ethAmount = 1 ether;
    bytes memory data = abi.encodeWithSelector(MockTarget.payableFunction.selector);

    // Fund the timelock
    vm.deal(address(timelock), ethAmount);

    // Schedule the call
    vm.startPrank(proposer1);
    timelock.schedule(address(target), ethAmount, data, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Fast forward time
    vm.warp(block.timestamp + MIN_DELAY + 1);

    uint256 initialBalance = address(target).balance;

    // Execute the call
    vm.startPrank(proposer1);
    timelock.execute(address(target), ethAmount, data, bytes32(0), bytes32(0));
    vm.stopPrank();

    // Verify ETH was transferred
    assertEq(address(target).balance, initialBalance + ethAmount);
  }

  function test_schedule_and_cancel() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(123));

    // Schedule the call
    vm.startPrank(proposer1);
    bytes32 operationId = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Verify operation is scheduled
    assertTrue(timelock.isOperationPending(operationId));

    // Cancel the operation (proposers can cancel)
    vm.prank(proposer1);
    timelock.cancel(operationId);

    // Verify operation is cancelled
    assertFalse(timelock.isOperation(operationId));
  }

  function test_schedule_batch_operations() public {
    address[] memory targets = new address[](2);
    uint256[] memory values = new uint256[](2);
    bytes[] memory payloads = new bytes[](2);

    targets[0] = address(target);
    targets[1] = address(target);
    values[0] = 0;
    values[1] = 0;
    payloads[0] = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(100));
    payloads[1] = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(200));

    // Schedule batch
    vm.startPrank(proposer1);
    bytes32 operationId = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));
    timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Verify batch is scheduled
    assertTrue(timelock.isOperationPending(operationId));

    // Fast forward time
    vm.warp(block.timestamp + MIN_DELAY + 1);

    // Execute batch
    vm.prank(proposer1);
    timelock.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));

    // Verify both operations were executed
    assertTrue(timelock.isOperationDone(operationId));
    assertEq(target.value(), 200); // Last operation overwrites
  }

  function test_schedule_with_predecessor() public {
    bytes memory data1 = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(10));
    bytes memory data2 = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(20));

    // Schedule first operation
    vm.startPrank(proposer1);
    bytes32 operation1 = timelock.hashOperation(address(target), 0, data1, bytes32(0), bytes32(0));
    timelock.schedule(address(target), 0, data1, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Schedule second operation with first as predecessor
    vm.startPrank(proposer1);
    bytes32 operation2 = timelock.hashOperation(address(target), 0, data2, operation1, bytes32(0));
    timelock.schedule(address(target), 0, data2, operation1, bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Fast forward time
    vm.warp(block.timestamp + MIN_DELAY + 1);

    // Both operations should be ready (predecessor dependency is checked at execution time)
    assertTrue(timelock.isOperationReady(operation1));
    assertTrue(timelock.isOperationReady(operation2));

    // Execute first operation
    vm.prank(proposer1);
    timelock.execute(address(target), 0, data1, bytes32(0), bytes32(0));

    // Execute second operation
    vm.prank(proposer1);
    timelock.execute(address(target), 0, data2, operation1, bytes32(0));

    // Verify both operations completed
    assertTrue(timelock.isOperationDone(operation1));
    assertTrue(timelock.isOperationDone(operation2));
    assertEq(target.value(), 20);
  }

  function test_only_proposer_can_schedule() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(42));

    // Non-proposer should not be able to schedule
    vm.prank(user1);
    vm.expectRevert();
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
  }

  function test_only_executor_can_execute() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(42));

    // Schedule operation
    vm.prank(proposer1);
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

    // Fast forward time
    vm.warp(block.timestamp + MIN_DELAY + 1);

    // Non-executor should not be able to execute
    vm.prank(user1);
    vm.expectRevert();
    timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
  }

  function test_only_cancellers_can_cancel() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(42));

    // Schedule operation
    vm.startPrank(proposer1);
    bytes32 operationId = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Non-canceller (admin) should not be able to cancel
    vm.prank(admin);
    vm.expectRevert();
    timelock.cancel(operationId);
  }

  function test_cannot_execute_before_delay() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(42));

    // Schedule operation
    vm.prank(proposer1);
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

    // Try to execute immediately (should fail)
    vm.prank(proposer1);
    vm.expectRevert();
    timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
  }

  function test_execute_failed_call() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.revertFunction.selector);

    // Schedule operation
    vm.prank(proposer1);
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

    // Fast forward time
    vm.warp(block.timestamp + MIN_DELAY + 1);

    // Execute should fail
    vm.prank(proposer1);
    vm.expectRevert("MockTarget: intentional revert");
    timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
  }

  function test_update_delay() public {
    uint256 newDelay = 7200; // 2 hours

    // Only the timelock contract itself can update delay (self-administration)
    // This would typically be done through a timelocked operation
    vm.prank(address(timelock));
    timelock.updateDelay(newDelay);

    assertEq(timelock.getMinDelay(), newDelay);
  }

  function test_only_timelock_can_update_delay() public {
    uint256 newDelay = 7200;

    // Only the timelock contract itself can update delay
    vm.prank(proposer1);
    vm.expectRevert();
    timelock.updateDelay(newDelay);

    // Admin also cannot update delay directly
    vm.prank(admin);
    vm.expectRevert();
    timelock.updateDelay(newDelay);
  }

  function test_grant_role() public {
    // Admin can grant roles
    vm.prank(admin);
    timelock.grantRole(EXECUTOR_ROLE, user1);

    assertTrue(timelock.hasRole(EXECUTOR_ROLE, user1));
  }

  function test_revoke_role() public {
    // Grant role first
    vm.prank(admin);
    timelock.grantRole(EXECUTOR_ROLE, user1);

    // Revoke role
    vm.prank(admin);
    timelock.revokeRole(EXECUTOR_ROLE, user1);

    assertFalse(timelock.hasRole(EXECUTOR_ROLE, user1));
  }

  function test_role_member_count() public {
    // In TimelockController, admin is also added to DEFAULT_ADMIN_ROLE
    // The exact count depends on OpenZeppelin's implementation
    assertTrue(timelock.getRoleMemberCount(ADMIN_ROLE) >= 1);
    assertEq(timelock.getRoleMemberCount(PROPOSER_ROLE), 2);
    assertEq(timelock.getRoleMemberCount(EXECUTOR_ROLE), 2);
    assertEq(timelock.getRoleMemberCount(CANCELLER_ROLE), 2);
  }

  function test_get_role_member() public {
    // Check that admin is in the admin role (order may vary)
    bool adminFound = false;
    uint256 adminCount = timelock.getRoleMemberCount(ADMIN_ROLE);
    for (uint256 i = 0; i < adminCount; i++) {
      if (timelock.getRoleMember(ADMIN_ROLE, i) == admin) {
        adminFound = true;
        break;
      }
    }
    assertTrue(adminFound);

    // Order may vary, so just check that both are present
    assertTrue(
      timelock.getRoleMember(PROPOSER_ROLE, 0) == proposer1 || timelock.getRoleMember(PROPOSER_ROLE, 0) == proposer2
    );
    assertTrue(
      timelock.getRoleMember(PROPOSER_ROLE, 1) == proposer1 || timelock.getRoleMember(PROPOSER_ROLE, 1) == proposer2
    );
  }

  function test_supports_interface() public {
    // Should support AccessControlEnumerable interface
    assertTrue(timelock.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    // Should support IERC165 interface
    assertTrue(timelock.supportsInterface(type(IERC165).interfaceId));
  }

  function test_fuzz_schedule_execute(uint256 value, uint256 delay) public {
    // Bound values to reasonable ranges
    value = bound(value, 0, 1_000_000);
    delay = bound(delay, MIN_DELAY, MIN_DELAY * 10);

    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, value);

    // Schedule operation (use proposer1 which has the required role)
    vm.prank(proposer1);
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), delay);

    // Fast forward time
    vm.warp(block.timestamp + delay + 1);

    // Execute operation (use proposer1 which has executor role)
    vm.startPrank(proposer1);
    timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    vm.stopPrank();

    // Verify execution
    assertEq(target.value(), value);
  }

  function test_fuzz_role_management(address newUser) public {
    vm.assume(newUser != address(0));
    vm.assume(newUser != admin);
    vm.assume(newUser != proposer1);
    vm.assume(newUser != proposer2);

    // Grant role
    vm.prank(admin);
    timelock.grantRole(EXECUTOR_ROLE, newUser);

    assertTrue(timelock.hasRole(EXECUTOR_ROLE, newUser));

    // Revoke role
    vm.prank(admin);
    timelock.revokeRole(EXECUTOR_ROLE, newUser);

    assertFalse(timelock.hasRole(EXECUTOR_ROLE, newUser));
  }

  function test_multiple_operations_same_target() public {
    uint256[] memory values = new uint256[](3);
    values[0] = 10;
    values[1] = 20;
    values[2] = 30;

    for (uint256 i = 0; i < values.length; i++) {
      bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, values[i]);

      // Schedule operation
      vm.startPrank(proposer1);
      timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
      vm.stopPrank();

      // Fast forward time
      vm.warp(block.timestamp + MIN_DELAY + 1);

      // Execute operation
      vm.startPrank(proposer1);
      timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
      vm.stopPrank();

      // Verify value is set
      assertEq(target.value(), values[i]);
    }
  }

  function test_operation_hash_consistency() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(42));

    // Hash operation before scheduling
    bytes32 hash1 = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

    // Schedule operation
    vm.startPrank(proposer1);
    bytes32 hash2 = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Hashes should be the same
    assertEq(hash1, hash2);
  }

  function test_cannot_execute_already_executed_operation() public {
    bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(42));

    // Schedule and execute operation
    vm.prank(proposer1);
    timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

    vm.warp(block.timestamp + MIN_DELAY + 1);

    vm.startPrank(proposer1);
    timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    vm.stopPrank();

    // Try to execute again (should fail)
    vm.prank(proposer1);
    vm.expectRevert();
    timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
  }

  function test_insufficient_eth_for_execution() public {
    uint256 ethAmount = 1 ether;
    bytes memory data = abi.encodeWithSelector(MockTarget.payableFunction.selector);

    // Schedule operation with ETH
    vm.startPrank(proposer1);
    timelock.schedule(address(target), ethAmount, data, bytes32(0), bytes32(0), MIN_DELAY);
    vm.stopPrank();

    // Fast forward time
    vm.warp(block.timestamp + MIN_DELAY + 1);

    // Try to execute without funding timelock (should fail)
    vm.prank(proposer1);
    vm.expectRevert();
    timelock.execute(address(target), ethAmount, data, bytes32(0), bytes32(0));
  }
}
