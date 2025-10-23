// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeApproval} from "contracts/utils/SafeApproval.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract SafeApprovalWrapper {
  using SafeApproval for IERC20;

  function clearAllApprovals(IERC20[] memory tokens, address[] memory spenders) external {
    SafeApproval.clearAllApprovals(tokens, spenders);
  }
}

contract SafeApprovalTest is Test {
  SafeApprovalWrapper public wrapper;
  MockERC20 public token;
  address public spender1;
  address public spender2;
  address public user;

  function setUp() public {
    wrapper = new SafeApprovalWrapper();
    token = new MockERC20("Test Token", "TEST", 18);
    spender1 = address(0x1);
    spender2 = address(0x2);
    user = address(this);

    // Mint tokens to the test contract
    token.mint(user, 1_000_000 * 1e18);
  }

  function test_safeApprove_resetsExistingApproval() public {
    // First approve a large amount
    token.approve(spender1, type(uint256).max);
    assertEq(token.allowance(user, spender1), type(uint256).max);

    // Now use safe approval for a smaller amount
    uint256 exactAmount = 1000 * 1e18;
    SafeApproval.safeApprove(token, spender1, exactAmount);

    // Should be exactly the amount we requested
    assertEq(token.allowance(user, spender1), exactAmount);
  }

  function test_safeApprove_noExistingApproval() public {
    // No existing approval
    assertEq(token.allowance(user, spender1), 0);

    uint256 exactAmount = 1000 * 1e18;
    SafeApproval.safeApprove(token, spender1, exactAmount);

    // Should be exactly the amount we requested
    assertEq(token.allowance(user, spender1), exactAmount);
  }

  function test_resetApproval() public {
    // Set an approval first
    token.approve(spender1, 1000 * 1e18);
    assertEq(token.allowance(user, spender1), 1000 * 1e18);

    // Reset it
    SafeApproval.resetApproval(token, spender1);
    assertEq(token.allowance(user, spender1), 0);
  }

  function test_resetApproval_noExistingApproval() public {
    // No existing approval
    assertEq(token.allowance(user, spender1), 0);

    // Reset should not fail
    SafeApproval.resetApproval(token, spender1);
    assertEq(token.allowance(user, spender1), 0);
  }

  function test_approveIfNeeded_sufficientAllowance() public {
    // Set sufficient allowance
    uint256 existingAmount = 2000 * 1e18;
    token.approve(spender1, existingAmount);

    uint256 requestedAmount = 1000 * 1e18;
    bool approved = SafeApproval.approveIfNeeded(token, spender1, requestedAmount);

    // Should not have approved since allowance was sufficient
    assertFalse(approved);
    assertEq(token.allowance(user, spender1), existingAmount);
  }

  function test_approveIfNeeded_insufficientAllowance() public {
    // Set insufficient allowance
    uint256 existingAmount = 500 * 1e18;
    token.approve(spender1, existingAmount);

    uint256 requestedAmount = 1000 * 1e18;
    bool approved = SafeApproval.approveIfNeeded(token, spender1, requestedAmount);

    // Should have approved since allowance was insufficient
    assertTrue(approved);
    assertEq(token.allowance(user, spender1), requestedAmount);
  }

  function test_clearAllApprovals() public {
    // Set approvals for multiple tokens and spenders
    MockERC20 token2 = new MockERC20("Test Token 2", "TEST2", 18);
    token2.mint(user, 1_000_000 * 1e18);

    token.approve(spender1, 1000 * 1e18);
    token.approve(spender2, 2000 * 1e18);
    token2.approve(spender1, 3000 * 1e18);
    token2.approve(spender2, 4000 * 1e18);

    // Verify approvals exist
    assertEq(token.allowance(user, spender1), 1000 * 1e18);
    assertEq(token.allowance(user, spender2), 2000 * 1e18);
    assertEq(token2.allowance(user, spender1), 3000 * 1e18);
    assertEq(token2.allowance(user, spender2), 4000 * 1e18);

    // Clear all approvals - need to clear each token with each spender
    IERC20[] memory tokens = new IERC20[](4);
    address[] memory spenders = new address[](4);
    tokens[0] = token;
    tokens[1] = token;
    tokens[2] = token2;
    tokens[3] = token2;
    spenders[0] = spender1;
    spenders[1] = spender2;
    spenders[2] = spender1;
    spenders[3] = spender2;

    SafeApproval.clearAllApprovals(tokens, spenders);

    // Verify all approvals are cleared
    assertEq(token.allowance(user, spender1), 0);
    assertEq(token.allowance(user, spender2), 0);
    assertEq(token2.allowance(user, spender1), 0);
    assertEq(token2.allowance(user, spender2), 0);
  }

  function test_clearTokenApprovals() public {
    // Set approvals for multiple spenders
    token.approve(spender1, 1000 * 1e18);
    token.approve(spender2, 2000 * 1e18);

    // Verify approvals exist
    assertEq(token.allowance(user, spender1), 1000 * 1e18);
    assertEq(token.allowance(user, spender2), 2000 * 1e18);

    // Clear approvals for this token
    address[] memory spenders = new address[](2);
    spenders[0] = spender1;
    spenders[1] = spender2;

    SafeApproval.clearTokenApprovals(token, spenders);

    // Verify all approvals are cleared
    assertEq(token.allowance(user, spender1), 0);
    assertEq(token.allowance(user, spender2), 0);
  }

  function test_clearAllApprovals_arrayLengthMismatch() public {
    IERC20[] memory tokens = new IERC20[](1);
    address[] memory spenders = new address[](2);

    // This should revert due to array length mismatch
    vm.expectRevert(bytes("Arrays length mismatch"));
    wrapper.clearAllApprovals(tokens, spenders);
  }
}
