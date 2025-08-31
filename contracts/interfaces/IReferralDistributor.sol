// SPDX-License-Identifier: AGPL-3.0-or-later

// ▗▖   ▗▞▀▚▖█ ▄ ▗▞▀▚▖▄   ▄ ▗▞▀▚▖
// ▐▌   ▐▛▀▀▘█ ▄ ▐▛▀▀▘█   █ ▐▛▀▀▘
// ▐▛▀▚▖▝▚▄▄▖█ █ ▝▚▄▄▖ ▀▄▀  ▝▚▄▄▖
// ▐▙▄▞▘     █ █

// ▄ ▄▄▄▄
// ▄ █   █
// █ █   █
// █

//  ▄▄▄  ▄▄▄  ▄▄▄▄  ▗▄▄▄▖▗▄▄▄▖▗▖ ▗▖▄ ▄▄▄▄
// ▀▄▄  █   █ █ █ █ ▐▌     █  ▐▌ ▐▌▄ █   █
// ▄▄▄▀ ▀▄▄▄▀ █   █ ▐▛▀▀▘  █  ▐▛▀▜▌█ █   █
//                  ▐▙▄▄▖  █  ▐▌ ▐▌█     ▗▄▖
//                                      ▐▌ ▐▌
//                                       ▝▀▜▌
//                                      ▐▙▄▞▘

// Website: https://something.fun

pragma solidity ^0.8.0;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title IReferralDistributor Interface
/// @notice Interface for distributing referral fees
interface IReferralDistributor {
  /// @notice Collects referral fees from the caller
  /// @param _token0 The token0 address
  /// @param _token1 The token1 address
  /// @param _amount0 The amount of token0 collected
  /// @param _amount1 The amount of token1 collected
  function collectReferralFees(address _token0, address _token1, uint256 _amount0, uint256 _amount1) external;

  /// @notice Distributes referral fees to the referral destination
  /// @param _distribution The referral distribution
  function distributeReferralFees(ReferralDistribution memory _distribution) external;

  /// @notice Distributes multiple referral fees to the referral destination
  /// @param _distributions The array of referral distributions
  function distributeReferralFeesMultiple(ReferralDistribution[] memory _distributions) external;

  /// @notice Emitted when referral fees are collected
  /// @param _token0 The token0 address
  /// @param _token1 The token1 address
  /// @param _amount0 The amount of token0 collected
  /// @param _amount1 The amount of token1 collected
  event ReferralFeesCollected(address indexed _token0, address indexed _token1, uint256 _amount0, uint256 _amount1);

  /// @notice Distributes referral fees to the referral destination
  /// @param _token0 The token0 address
  /// @param _token1 The token1 address
  /// @param _amount0 The amount of token0 to distribute
  /// @param _amount1 The amount of token1 to distribute
  /// @param _destination The destination address
  struct ReferralDistribution {
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
    address destination;
  }

  /// @notice Emitted when referral fees are distributed
  /// @param _distribution The referral distribution
  event ReferralFeesDistributed(ReferralDistribution _distribution);
}
