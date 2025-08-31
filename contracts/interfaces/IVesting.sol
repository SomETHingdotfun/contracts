// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

/**
 * @title IVesting
 * @notice Interface for the Vesting contract that handles token vesting schedules
 */
interface IVesting {
  // Vesting info structure
  struct VestingInfo {
    uint256 startTime; // When vesting began
    uint256 totalAmount; // Total amount to vest
    uint256 upfrontAmount; // Amount released upfront (25%)
    uint256 vestedAmount; // Amount already released during vesting
  }

  // Events
  event TokenVestingStarted(address indexed token, address indexed account, uint256 total, uint256 upfront);
  event TokenVestingClaimed(address indexed token, address indexed account, uint256 amount);

  /**
   * @notice Starts vesting for an account
   * @param _token The token to vest
   * @param _receiver The receiving address
   * @param _amount The total amount to vest
   */
  function createVest(address _token, address _receiver, uint256 _amount) external;

  /**
   * @notice Claim vested tokens
   * @param _token The token to claim
   */
  function claimVestedTokens(address _token) external;

  /**
   * @notice Calculate releasable amount based on vesting schedule
   * @param _token The token address
   * @param _account The account address
   * @return Amount that can be released
   */
  function calculateClaimableAmount(address _token, address _account) external view returns (uint256);

  /**
   * @notice Get vesting info for an account
   * @param _token The token address
   * @param _account The account address
   * @return startTime When vesting began
   * @return totalAmount Total amount to vest
   * @return upfrontAmount Amount released upfront
   * @return vestedAmount Amount already released during vesting
   * @return claimableAmount Amount currently claimable
   */
  function getVestingInfo(address _token, address _account)
    external
    view
    returns (
      uint256 startTime,
      uint256 totalAmount,
      uint256 upfrontAmount,
      uint256 vestedAmount,
      uint256 claimableAmount
    );

  /**
   * @notice Admin function to rescue tokens sent to this contract by mistake
   * @param _token The token to rescue
   * @param _to The recipient address
   */
  function emergencyWithdrawal(address _token, address _to) external;
}
