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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IClPool} from "contracts/interfaces/thirdparty/IClPool.sol";

/// @title Concentrated Liquidity Market Maker Adapter Interface
/// @notice Interface for interacting with concentrated liquidity pools
/// @dev Implements single-sided liquidity provision and fee claiming
interface ICLMMAdapter {
  /// @notice Parameters for adding liquidity to a pool
    struct AddLiquidityParams {
    IERC20 tokenBase;
    IERC20 tokenQuote;
    int24 tick0;
    int24 tick1;
    int24 tick2;
  }
  
  /// @notice Emitted when single-sided liquidity is added
  /// @param token The base token address
  /// @param pool The pool address
  /// @param tick0 The first tick
  /// @param tick1 The second tick
  /// @param tick2 The third tick
  /// @param tokenId0 The NFT token ID for first position
  /// @param tokenId1 The NFT token ID for second position
  event LiquidityAdded(
    address indexed token,
    address indexed pool,
    int24 tick0,
    int24 tick1,
    int24 tick2,
    uint256 tokenId0,
    uint256 tokenId1
  );

  /// @notice Emitted when a swap with exact input is executed
  /// @param tokenIn The input token address
  /// @param tokenOut The output token address
  /// @param amountIn The amount of input tokens
  /// @param amountOut The amount of output tokens
  /// @param recipient The recipient address
  event SwapExecutedExactInput(
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    address indexed recipient
  );

  /// @notice Emitted when a swap with exact output is executed
  /// @param tokenIn The input token address
  /// @param tokenOut The output token address
  /// @param amountIn The amount of input tokens
  /// @param amountOut The amount of output tokens
  /// @param recipient The recipient address
  event SwapExecutedExactOutput(
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    address indexed recipient
  );

  /// @notice Thrown when caller is not the launchpad contract
  error Unauthorized();

  /// @notice Thrown when tick ordering is invalid (tick0 must be < tick1 < tick2)
  error InvalidTickOrdering();

  /// @notice Thrown when a tick is not aligned to the tick spacing
  /// @param tick The tick that is not aligned
  error TickNotAligned(int24 tick);

  /// @notice Thrown when tick0 is not greater than MIN_TICK
  /// @param tick0 The provided tick0
  /// @param minTick The minimum allowed tick
  error Tick0OutOfRange(int24 tick0, int24 minTick);

  /// @notice Thrown when tick2 is not less than MAX_TICK
  /// @param tick2 The provided tick2
  /// @param maxTick The maximum allowed tick
  error Tick2OutOfRange(int24 tick2, int24 maxTick);

  /// @notice Add single-sided liquidity to a concentrated pool
  /// @dev Provides liquidity across three ticks with different amounts
  /// @return pool The address of the pool
  function addSingleSidedLiquidity(AddLiquidityParams memory _params) external returns (address pool);

  /// @notice Swap a token with exact output
  /// @param _tokenIn The token to swap
  /// @param _tokenOut The token to receive
  /// @param _amountOut The amount of tokens to swap
  /// @param _maxAmountIn The maximum amount of tokens to receive
  /// @param _sqrtPriceLimitX96 The price limit for the swap (0 = no limit)
  /// @return amountIn The amount of tokens received
  function swapWithExactOutput(
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _amountOut,
    uint256 _maxAmountIn,
    uint160 _sqrtPriceLimitX96
  ) external returns (uint256 amountIn);

  /// @notice Swap a token with exact input
  /// @param _tokenIn The token to swap
  /// @param _tokenOut The token to receive
  /// @param _amountIn The amount of tokens to swap
  /// @param _minAmountOut The minimum amount of tokens to receive
  /// @param _sqrtPriceLimitX96 The price limit for the swap (0 = no limit)
  /// @return amountOut The amount of tokens received
  function swapWithExactInput(
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _amountIn,
    uint256 _minAmountOut,
    uint160 _sqrtPriceLimitX96
  ) external returns (uint256 amountOut);

  /// @notice Returns the address of the Launchpad contract
  /// @return launchpad The address of the Launchpad contract
  function launchpad() external view returns (address launchpad);

  /// @notice Claim accumulated fees from the pool
  /// @param _token The token address to claim fees for
  /// @return fee0 The amount of token0 fees to claim
  /// @return fee1 The amount of token1 fees to claim
  function claimFees(address _token) external returns (uint256 fee0, uint256 fee1);

  /// @notice claimed fees from the pool
  /// @param _token The token address to claim fees for
  /// @return fee0 The amount of token0 fees to claim
  /// @return fee1 The amount of token1 fees to claim
  function claimedFees(address _token) external view returns (uint256 fee0, uint256 fee1);
}
