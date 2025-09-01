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

import "./pool/IClPoolActions.sol";
import "./pool/IClPoolDerivedState.sol";
import "./pool/IClPoolImmutables.sol";
import "./pool/IClPoolOwnerActions.sol";
import "./pool/IClPoolState.sol";

/// @title The interface for a CL V2 Pool
/// @notice A CL pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IClPool is IClPoolImmutables, IClPoolState, IClPoolDerivedState, IClPoolActions, IClPoolOwnerActions {
  /// @notice Initializes a pool with parameters provided
  function initialize(
    address _factory,
    address _nfpManager,
    address _veRam,
    address _voter,
    address _token0,
    address _token1,
    uint24 _fee,
    int24 _tickSpacing
  ) external;
}
