// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAirdropRewarder
 * @notice Interface for the AirdropRewarder contract that handles token airdrops using Merkle proofs
 */
interface IAirdropRewarder {
  // Events
  event MerkleRootSet(address indexed token, bytes32 merkleRoot);
  event RewardsClaimed(address indexed token, address indexed account, uint256 amount);

  // Errors
  error InvalidAddress();
  error MerkleRootAlreadySet();
  error AlreadyClaimed();
  error InvalidMerkleProof(bytes32[]);
  error MerkleRootNotSet();
  error InvalidRoot();
  error OnlyLaunchpadCanSetMerkleRoot();

  /**
   * @notice Initialize the contract
   * @param _launchpad Address of the launchpad contract
   */
  function initialize(address _launchpad) external;

  /**
   * @notice Set the launchpad address
   * @param _launchpad Address of the launchpad contract
   */
  function setLaunchpad(address _launchpad) external;

  /**
   * @notice Set the airdrop amount
   * @param _token Address of the token
   * @param _amount Amount of tokens to airdrop
   */
  function setAirdropAmount(address _token, uint256 _amount) external;

  /**
   * @notice Set the Merkle root for a token
   * @param _token Address of the token
   * @param _merkleRoot Merkle root for the token's airdrop
   */
  function setMerkleRoot(address _token, bytes32 _merkleRoot) external;

  /**
   * @notice Claim airdropped tokens
   * @param _token Address of the token to claim
   * @param _user Address that should receive the tokens
   * @param _claimAmount Amount of tokens to claim
   * @param _merkleProofs Merkle proof array
   */
  function claim(address _token, address _user, uint256 _claimAmount, bytes32[] calldata _merkleProofs) external;

  /**
   * @notice Emergency withdrawal of tokens (admin only)
   * @param token Token to transfer
   * @param to Recipient address
   */
  function emergencyWithdrawal(address token, address to) external;
}
