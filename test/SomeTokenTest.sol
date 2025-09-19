// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SomeToken} from "contracts/SomeToken.sol";
import {Test} from "lib/forge-std/src/Test.sol";

import "forge-std/console.sol";

contract SomeTokenTest is Test {
  SomeToken token;
  address owner;
  address user1;
  address user2;

  function setUp() public {
    owner = makeAddr("owner");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");

    // Deploy the token with test name and symbol
    vm.prank(owner);
    token = new SomeToken("Test Token", "TEST");
  }

  function test_initialization() public {
    // Test token name and symbol
    assertEq(token.name(), "Test Token");
    assertEq(token.symbol(), "TEST");
    assertEq(token.decimals(), 18);

    // Test initial supply
    uint256 expectedSupply = 1_000_000_000 * 1e18; // 1 billion tokens
    assertEq(token.totalSupply(), expectedSupply);

    // Test that owner receives all tokens initially
    assertEq(token.balanceOf(owner), expectedSupply);
  }

  function test_ownership() public {
    // Test that ownership is renounced (transferred to address(0))
    assertEq(token.owner(), address(0));

    // Test that only owner can call owner functions (should fail since owner is address(0))
    vm.expectRevert();
    token.transferOwnership(user1);
  }

  function test_erc20_functionality() public {
    // Test transfer
    uint256 transferAmount = 1000 * 1e18;
    vm.prank(owner);
    token.transfer(user1, transferAmount);

    assertEq(token.balanceOf(user1), transferAmount);
    assertEq(token.balanceOf(owner), 1_000_000_000 * 1e18 - transferAmount);

    // Test approval and transferFrom
    vm.prank(user1);
    token.approve(user2, transferAmount);

    assertEq(token.allowance(user1, user2), transferAmount);

    vm.prank(user2);
    token.transferFrom(user1, user2, transferAmount);

    assertEq(token.balanceOf(user2), transferAmount);
    assertEq(token.balanceOf(user1), 0);
    assertEq(token.allowance(user1, user2), 0);
  }

  function test_transfer_insufficient_balance() public {
    uint256 transferAmount = 1_000_000_001 * 1e18; // More than total supply

    vm.prank(owner);
    vm.expectRevert();
    token.transfer(user1, transferAmount);
  }

  function test_transferFrom_insufficient_allowance() public {
    uint256 transferAmount = 1000 * 1e18;

    // First transfer some tokens to user1
    vm.prank(owner);
    token.transfer(user1, transferAmount);

    // Try to transferFrom without approval
    vm.prank(user2);
    vm.expectRevert();
    token.transferFrom(user1, user2, transferAmount);
  }

  function test_transferFrom_insufficient_balance() public {
    uint256 transferAmount = 1000 * 1e18;

    // First transfer some tokens to user1
    vm.prank(owner);
    token.transfer(user1, transferAmount);

    // Approve user2 to spend user1's tokens
    vm.prank(user1);
    token.approve(user2, transferAmount);

    // Transfer all tokens from user1 to user2
    vm.prank(user2);
    token.transferFrom(user1, user2, transferAmount);

    // Try to transfer more than user1 has (should fail)
    vm.prank(user2);
    vm.expectRevert();
    token.transferFrom(user1, user2, 1);
  }

  function test_approve() public {
    uint256 approveAmount = 1000 * 1e18;

    vm.prank(owner);
    token.approve(user1, approveAmount);

    assertEq(token.allowance(owner, user1), approveAmount);
  }

  function test_approve_updates() public {
    uint256 initialAmount = 500 * 1e18;
    uint256 newAmount = 800 * 1e18;

    // Initial approval
    vm.prank(owner);
    token.approve(user1, initialAmount);
    assertEq(token.allowance(owner, user1), initialAmount);

    // Update approval
    vm.prank(owner);
    token.approve(user1, newAmount);
    assertEq(token.allowance(owner, user1), newAmount);
  }

  function test_transfer_to_zero_address() public {
    uint256 transferAmount = 1000 * 1e18;

    vm.prank(owner);
    vm.expectRevert();
    token.transfer(address(0), transferAmount);
  }

  function test_transferFrom_to_zero_address() public {
    uint256 transferAmount = 1000 * 1e18;

    // First transfer some tokens to user1
    vm.prank(owner);
    token.transfer(user1, transferAmount);

    // Approve user2 to spend user1's tokens
    vm.prank(user1);
    token.approve(user2, transferAmount);

    // Try to transfer to zero address
    vm.prank(user2);
    vm.expectRevert();
    token.transferFrom(user1, address(0), transferAmount);
  }

  function test_approve_zero_address() public {
    uint256 approveAmount = 1000 * 1e18;

    vm.prank(owner);
    vm.expectRevert();
    token.approve(address(0), approveAmount);
  }

  function test_totalSupply_immutable() public {
    uint256 initialSupply = token.totalSupply();

    // Transfer some tokens
    vm.prank(owner);
    token.transfer(user1, 1000 * 1e18);

    // Total supply should remain the same
    assertEq(token.totalSupply(), initialSupply);
  }

  function test_balanceOf() public {
    uint256 initialBalance = token.balanceOf(owner);
    assertEq(initialBalance, 1_000_000_000 * 1e18);

    // Check balance of address with no tokens
    assertEq(token.balanceOf(user1), 0);
  }

  function test_events() public {
    uint256 transferAmount = 1000 * 1e18;

    // Test Transfer event
    vm.expectEmit(true, true, true, true);
    emit IERC20.Transfer(owner, user1, transferAmount);

    vm.prank(owner);
    token.transfer(user1, transferAmount);

    // Test Approval event
    uint256 approveAmount = 500 * 1e18;
    vm.expectEmit(true, true, true, true);
    emit IERC20.Approval(owner, user1, approveAmount);

    vm.prank(owner);
    token.approve(user1, approveAmount);
  }

  function test_renounceOwnership() public {
    // Since ownership is already renounced in constructor,
    // we can't test renounceOwnership directly
    // But we can verify that owner is address(0)
    assertEq(token.owner(), address(0));
  }

  function test_constructor_parameters() public {
    // Test with different name and symbol
    SomeToken customToken = new SomeToken("Custom Token", "CUSTOM");

    assertEq(customToken.name(), "Custom Token");
    assertEq(customToken.symbol(), "CUSTOM");
    assertEq(customToken.decimals(), 18);
    assertEq(customToken.totalSupply(), 1_000_000_000 * 1e18);
  }

  function test_fuzz_transfer(uint256 amount) public {
    // Bound the amount to reasonable values
    amount = bound(amount, 1, token.balanceOf(owner));

    uint256 initialBalanceOwner = token.balanceOf(owner);
    uint256 initialBalanceUser1 = token.balanceOf(user1);

    vm.prank(owner);
    token.transfer(user1, amount);

    assertEq(token.balanceOf(owner), initialBalanceOwner - amount);
    assertEq(token.balanceOf(user1), initialBalanceUser1 + amount);
  }

  function test_fuzz_approve(uint256 amount) public {
    // Bound the amount to reasonable values
    amount = bound(amount, 0, 1_000_000_000 * 1e18);

    vm.prank(owner);
    token.approve(user1, amount);

    assertEq(token.allowance(owner, user1), amount);
  }
}
