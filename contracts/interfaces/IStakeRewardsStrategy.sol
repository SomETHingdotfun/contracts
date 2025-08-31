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

/// @title IStakeRewardsStrategy Interface
/// @notice Interface for implementing custom reward distribution strategies for staked positions
interface IStakeRewardsStrategy {
  /// @notice Configuration data for rewards distribution
  /// @param targetToken The token address that rewards will be distributed in
  /// @param extraData Additional encoded data needed for the specific rewards strategy
  struct RewardsConfigData {
    address targetToken;
    bytes extraData;
  }

  /// @notice Distributes rewards for a staked position
  /// @dev Implementations should handle converting fees to rewards and distributing them
  /// @param _token0 The address of the first token in the position
  /// @param _token1 The address of the second token in the position
  /// @param _amount0 The amount of _token0 fees collected
  /// @param _amount1 The amount of _token1 fees collected
  /// @param _data Configuration data for the rewards distribution
  function distributeRewards(
    address _token0,
    address _token1,
    uint256 _amount0,
    uint256 _amount1,
    RewardsConfigData calldata _data
  ) external;
}
