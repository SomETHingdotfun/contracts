// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SafeApproval
 * @dev Utility library for safe token approvals to prevent unbounded approval vulnerabilities
 * @notice Implements the safe-approve pattern: set to 0, then set exact amount
 */
library SafeApproval {
    using SafeERC20 for IERC20;

    /**
     * @dev Safely approve a token for a spender using the safe-approve pattern
     * @param token The token to approve
     * @param spender The address to approve
     * @param amount The exact amount to approve
     */
    function safeApprove(IERC20 token, address spender, uint256 amount) internal {
        // First, set approval to 0 to reset any existing approval
        if (token.allowance(address(this), spender) > 0) {
            token.forceApprove(spender, 0);
        }
        
        // Then set the exact amount needed
        token.forceApprove(spender, amount);
    }

    /**
     * @dev Reset approval to 0 for a token and spender
     * @param token The token to reset approval for
     * @param spender The address to reset approval for
     */
    function resetApproval(IERC20 token, address spender) internal {
        if (token.allowance(address(this), spender) > 0) {
            token.forceApprove(spender, 0);
        }
    }

    /**
     * @dev Check if an approval is needed and perform safe approval
     * @param token The token to approve
     * @param spender The address to approve
     * @param amount The amount needed
     * @return true if approval was performed, false if sufficient allowance already exists
     */
    function approveIfNeeded(IERC20 token, address spender, uint256 amount) internal returns (bool) {
        uint256 currentAllowance = token.allowance(address(this), spender);
        
        if (currentAllowance < amount) {
            // Reset to 0 first if there's an existing approval
            if (currentAllowance > 0) {
                token.forceApprove(spender, 0);
            }
            // Set the exact amount needed
            token.forceApprove(spender, amount);
            return true;
        }
        
        return false;
    }

    /**
     * @dev Clear all approvals for multiple tokens and spenders
     * @param tokens Array of tokens to clear approvals for
     * @param spenders Array of spenders to clear approvals for
     * @notice Both arrays must have the same length
     */
    function clearAllApprovals(IERC20[] memory tokens, address[] memory spenders) internal {
        require(tokens.length == spenders.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            resetApproval(tokens[i], spenders[i]);
        }
    }

    /**
     * @dev Emergency function to clear all approvals for a token across multiple spenders
     * @param token The token to clear approvals for
     * @param spenders Array of spenders to clear approvals for
     */
    function clearTokenApprovals(IERC20 token, address[] memory spenders) internal {
        for (uint256 i = 0; i < spenders.length; i++) {
            resetApproval(token, spenders[i]);
        }
    }
}
