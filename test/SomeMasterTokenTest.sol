// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SomeMasterToken} from "contracts/SomeMasterToken.sol";
import {Test} from "lib/forge-std/src/Test.sol";

import "forge-std/console.sol";

contract SomeMasterTokenTest is Test {
  SomeMasterToken token;
  address deployer;
  address user1;
  address user2;
  address user3;

  // Constants
  uint256 constant TOTAL_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens
  string constant TOKEN_NAME = "Something.fun";
  string constant TOKEN_SYMBOL = "SOME";
  uint8 constant TOKEN_DECIMALS = 18;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  function setUp() public {
    deployer = makeAddr("deployer");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    user3 = makeAddr("user3");

    // Deploy the token
    vm.prank(deployer);
    token = new SomeMasterToken();
  }

  // ============ Constructor Tests ============

  function test_constructor_initialization() public {
    // Test token metadata
    assertEq(token.name(), TOKEN_NAME);
    assertEq(token.symbol(), TOKEN_SYMBOL);
    assertEq(token.decimals(), TOKEN_DECIMALS);

    // Test total supply
    assertEq(token.totalSupply(), TOTAL_SUPPLY);

    // Test that deployer receives all tokens
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY);
  }

  function test_constructor_minting() public {
    // Verify that tokens are minted to deployer
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY);

    // Verify no tokens are minted to other addresses
    assertEq(token.balanceOf(user1), 0);
    assertEq(token.balanceOf(user2), 0);
    assertEq(token.balanceOf(address(this)), 0);
  }

  // ============ ERC20 Basic Functionality Tests ============

  function test_transfer() public {
    uint256 transferAmount = 1000 * 1e18;

    // Record initial balances
    uint256 initialDeployerBalance = token.balanceOf(deployer);
    uint256 initialUser1Balance = token.balanceOf(user1);

    // Expect Transfer event
    vm.expectEmit(true, true, true, true);
    emit Transfer(deployer, user1, transferAmount);

    // Execute transfer
    vm.prank(deployer);
    bool success = token.transfer(user1, transferAmount);

    // Verify transfer was successful
    assertTrue(success);
    assertEq(token.balanceOf(deployer), initialDeployerBalance - transferAmount);
    assertEq(token.balanceOf(user1), initialUser1Balance + transferAmount);
  }

  function test_transfer_insufficient_balance() public {
    uint256 transferAmount = TOTAL_SUPPLY + 1; // More than total supply

    vm.prank(deployer);
    vm.expectRevert();
    token.transfer(user1, transferAmount);
  }

  function test_transfer_to_zero_address() public {
    uint256 transferAmount = 1000 * 1e18;

    vm.prank(deployer);
    vm.expectRevert();
    token.transfer(address(0), transferAmount);
  }

  function test_transfer_self() public {
    uint256 transferAmount = 1000 * 1e18;
    uint256 initialBalance = token.balanceOf(deployer);

    vm.prank(deployer);
    bool success = token.transfer(deployer, transferAmount);

    assertTrue(success);
    assertEq(token.balanceOf(deployer), initialBalance);
  }

  function test_approve() public {
    uint256 approveAmount = 500 * 1e18;

    // Expect Approval event
    vm.expectEmit(true, true, true, true);
    emit Approval(deployer, user1, approveAmount);

    // Execute approval
    vm.prank(deployer);
    bool success = token.approve(user1, approveAmount);

    assertTrue(success);
    assertEq(token.allowance(deployer, user1), approveAmount);
  }

  function test_approve_zero_address() public {
    uint256 approveAmount = 500 * 1e18;

    vm.prank(deployer);
    vm.expectRevert();
    token.approve(address(0), approveAmount);
  }

  function test_approve_self() public {
    uint256 approveAmount = 500 * 1e18;

    vm.prank(deployer);
    bool success = token.approve(deployer, approveAmount);

    assertTrue(success);
    assertEq(token.allowance(deployer, deployer), approveAmount);
  }

  function test_transferFrom() public {
    uint256 transferAmount = 1000 * 1e18;

    // First, transfer some tokens to user1
    vm.prank(deployer);
    token.transfer(user1, transferAmount);

    // User1 approves user2 to spend tokens
    vm.prank(user1);
    token.approve(user2, transferAmount);

    // Record initial balances
    uint256 initialUser1Balance = token.balanceOf(user1);
    uint256 initialUser2Balance = token.balanceOf(user2);
    uint256 initialAllowance = token.allowance(user1, user2);

    // Expect Transfer event
    vm.expectEmit(true, true, true, true);
    emit Transfer(user1, user2, transferAmount);

    // User2 transfers tokens from user1 to user2
    vm.prank(user2);
    bool success = token.transferFrom(user1, user2, transferAmount);

    assertTrue(success);
    assertEq(token.balanceOf(user1), initialUser1Balance - transferAmount);
    assertEq(token.balanceOf(user2), initialUser2Balance + transferAmount);
    assertEq(token.allowance(user1, user2), initialAllowance - transferAmount);
  }

  function test_transferFrom_insufficient_allowance() public {
    uint256 transferAmount = 1000 * 1e18;

    // Transfer tokens to user1
    vm.prank(deployer);
    token.transfer(user1, transferAmount);

    // Try to transferFrom without approval
    vm.prank(user2);
    vm.expectRevert();
    token.transferFrom(user1, user2, transferAmount);
  }

  function test_transferFrom_insufficient_balance() public {
    uint256 transferAmount = 1000 * 1e18;

    // Transfer tokens to user1
    vm.prank(deployer);
    token.transfer(user1, transferAmount);

    // User1 approves user2 for more than they have
    vm.prank(user1);
    token.approve(user2, transferAmount + 1);

    // Try to transfer more than user1 has
    vm.prank(user2);
    vm.expectRevert();
    token.transferFrom(user1, user2, transferAmount + 1);
  }

  function test_transferFrom_zero_address() public {
    uint256 transferAmount = 1000 * 1e18;

    // Transfer tokens to user1
    vm.prank(deployer);
    token.transfer(user1, transferAmount);

    // User1 approves user2
    vm.prank(user1);
    token.approve(user2, transferAmount);

    // Try to transfer to zero address
    vm.prank(user2);
    vm.expectRevert();
    token.transferFrom(user1, address(0), transferAmount);
  }

  // ============ Allowance Management Tests ============

  function test_allowance_updates() public {
    uint256 initialAmount = 100 * 1e18;
    uint256 newAmount = 200 * 1e18;

    // Set initial allowance
    vm.prank(deployer);
    token.approve(user1, initialAmount);
    assertEq(token.allowance(deployer, user1), initialAmount);

    // Update allowance to new amount
    vm.prank(deployer);
    token.approve(user1, newAmount);
    assertEq(token.allowance(deployer, user1), newAmount);

    // Set allowance to zero
    vm.prank(deployer);
    token.approve(user1, 0);
    assertEq(token.allowance(deployer, user1), 0);
  }

  // ============ Edge Cases and Error Conditions ============

  function test_transfer_max_uint256() public {
    // Try to transfer max uint256 (should fail due to insufficient balance)
    vm.prank(deployer);
    vm.expectRevert();
    token.transfer(user1, type(uint256).max);
  }

  function test_approve_max_uint256() public {
    // Approve max uint256
    vm.prank(deployer);
    bool success = token.approve(user1, type(uint256).max);

    assertTrue(success);
    assertEq(token.allowance(deployer, user1), type(uint256).max);
  }

  function test_multiple_transfers() public {
    uint256 transferAmount = 100 * 1e18;
    uint256 totalTransferred = 0;

    // Transfer to multiple users
    for (uint256 i = 0; i < 10; i++) {
      address user = makeAddr(string(abi.encodePacked("user", i)));

      vm.prank(deployer);
      token.transfer(user, transferAmount);
      totalTransferred += transferAmount;

      assertEq(token.balanceOf(user), transferAmount);
    }

    // Verify deployer's remaining balance
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY - totalTransferred);
  }

  function test_approval_race_condition() public {
    uint256 firstApproval = 100 * 1e18;
    uint256 secondApproval = 200 * 1e18;

    // First approval
    vm.prank(deployer);
    token.approve(user1, firstApproval);
    assertEq(token.allowance(deployer, user1), firstApproval);

    // Second approval (should overwrite the first)
    vm.prank(deployer);
    token.approve(user1, secondApproval);
    assertEq(token.allowance(deployer, user1), secondApproval);
  }

  // ============ Fuzz Tests ============

  function test_fuzz_transfer(uint256 amount) public {
    // Bound the amount to reasonable values
    amount = bound(amount, 1, token.balanceOf(deployer));

    uint256 initialDeployerBalance = token.balanceOf(deployer);
    uint256 initialUser1Balance = token.balanceOf(user1);

    vm.prank(deployer);
    token.transfer(user1, amount);

    assertEq(token.balanceOf(deployer), initialDeployerBalance - amount);
    assertEq(token.balanceOf(user1), initialUser1Balance + amount);
  }

  function test_fuzz_approve(uint256 amount) public {
    // Bound the amount to reasonable values (not max uint256 to avoid potential issues)
    amount = bound(amount, 0, 1_000_000_000 * 1e18);

    vm.prank(deployer);
    token.approve(user1, amount);

    assertEq(token.allowance(deployer, user1), amount);
  }

  function test_fuzz_transferFrom(uint256 amount) public {
    // First transfer some tokens to user1
    uint256 user1Balance = 1000 * 1e18;
    vm.prank(deployer);
    token.transfer(user1, user1Balance);

    // Bound the amount to what user1 actually has
    amount = bound(amount, 1, user1Balance);

    // User1 approves user2
    vm.prank(user1);
    token.approve(user2, amount);

    uint256 initialUser1Balance = token.balanceOf(user1);
    uint256 initialUser2Balance = token.balanceOf(user2);

    // User2 transfers from user1
    vm.prank(user2);
    token.transferFrom(user1, user2, amount);

    assertEq(token.balanceOf(user1), initialUser1Balance - amount);
    assertEq(token.balanceOf(user2), initialUser2Balance + amount);
    assertEq(token.allowance(user1, user2), 0);
  }

  // ============ Gas Optimization Tests ============

  function test_gas_transfer() public {
    uint256 transferAmount = 1000 * 1e18;

    // Measure gas for transfer
    vm.prank(deployer);
    uint256 gasStart = gasleft();
    token.transfer(user1, transferAmount);
    uint256 gasUsed = gasStart - gasleft();

    console.log("Gas used for transfer:", gasUsed);
    // Gas usage should be reasonable (typically around 21k for simple transfers)
    assertLt(gasUsed, 100_000);
  }

  function test_gas_approve() public {
    uint256 approveAmount = 1000 * 1e18;

    vm.prank(deployer);
    uint256 gasStart = gasleft();
    token.approve(user1, approveAmount);
    uint256 gasUsed = gasStart - gasleft();

    console.log("Gas used for approve:", gasUsed);
    assertLt(gasUsed, 100_000);
  }

  // ============ Integration Tests ============

  function test_full_transfer_cycle() public {
    uint256 amount = 1000 * 1e18;

    // 1. Deployer transfers to user1
    vm.prank(deployer);
    token.transfer(user1, amount);
    assertEq(token.balanceOf(user1), amount);

    // 2. User1 approves user2
    vm.prank(user1);
    token.approve(user2, amount);
    assertEq(token.allowance(user1, user2), amount);

    // 3. User2 transfers from user1 to user3
    vm.prank(user2);
    token.transferFrom(user1, user3, amount);
    assertEq(token.balanceOf(user1), 0);
    assertEq(token.balanceOf(user3), amount);
    assertEq(token.allowance(user1, user2), 0);

    // 4. User3 transfers back to deployer
    vm.prank(user3);
    token.transfer(deployer, amount);
    assertEq(token.balanceOf(user3), 0);
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY);
  }

  // ============ View Function Tests ============

  function test_view_functions() public {
    // Test that view functions return expected values
    assertEq(token.name(), TOKEN_NAME);
    assertEq(token.symbol(), TOKEN_SYMBOL);
    assertEq(token.decimals(), TOKEN_DECIMALS);
    assertEq(token.totalSupply(), TOTAL_SUPPLY);
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY);
    assertEq(token.allowance(deployer, user1), 0);
  }

  // ============ Contract State Tests ============

  function test_contract_state_consistency() public {
    // Ensure total supply remains constant
    assertEq(token.totalSupply(), TOTAL_SUPPLY);

    // Perform some operations
    vm.prank(deployer);
    token.transfer(user1, 1000 * 1e18);

    // Total supply should still be the same
    assertEq(token.totalSupply(), TOTAL_SUPPLY);

    // Sum of all balances should equal total supply
    uint256 totalBalances = token.balanceOf(deployer) + token.balanceOf(user1);
    assertEq(totalBalances, TOTAL_SUPPLY);
  }

  function test_no_minting_after_construction() public {
    // Verify that no additional tokens can be minted
    // (SomeMasterToken doesn't have a mint function, so this should pass)
    uint256 initialSupply = token.totalSupply();

    // Perform various operations
    vm.prank(deployer);
    token.transfer(user1, 1000 * 1e18);

    // Total supply should remain unchanged
    assertEq(token.totalSupply(), initialSupply);
  }
}
