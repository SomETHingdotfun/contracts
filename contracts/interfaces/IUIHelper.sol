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
import {ITokenLaunchpad} from "./ITokenLaunchpad.sol";
import {IOpenOceanCaller} from "./thirdparty/IOpenOcean.sol";

/// @title UI Helper Interface
/// @notice Interface for the UIHelper contract that facilitates token creation, buying, and selling with OpenOcean integration
interface IUIHelper is IOpenOceanCaller{
    /// @notice Parameters for OpenOcean aggregator integration
    struct OpenOceanParams {
        IERC20 tokenIn;
        uint256 tokenAmountIn;
        IERC20 tokenOut;
        uint256 minReturnAmount;
        uint256 guaranteedAmount;
        uint256 flags;
        address referrer;
        bytes permit;
        CallDescription[] calls;
    }
    struct InitialBalances {
        uint256 tokenIn;
        uint256 openOceanTokenIn;
        uint256 openOceanTokenOut;
        uint256 fundingToken;
        uint256 tokenOut;
    }

    /// @notice Thrown when no funding tokens were received after zap
    error NoFundingTokensReceived();

    /// @notice Thrown when the token in doesn't match the funding token
    error InvalidTokenIn();

    /// @notice Thrown when token amount in should be zero
    error TokenAmountInMustBeZero();

    /// @notice Thrown when ETH transfer fails
    error ETHTransferFailed();

    /// @notice Thrown when msg.value doesn't match the expected ETH amount
    error InvalidETHAmount();

    /// @notice Thrown when the OpenOcean aggregator call fails
    error OpenOceanCallFailed();

    /// @notice Thrown when received amount is less than minimum required
    /// @param received The amount received
    /// @param minimum The minimum amount required
    error InsufficientOutputAmount(uint256 received, uint256 minimum);

    /// @notice Creates a new token and buys it using OpenOcean for swapping
    /// @param _openOceanParams The parameters for the OpenOcean swap
    /// @param _params The token creation parameters
    /// @param _expected The expected token address (0 for no validation)
    /// @param _amount The amount of funding token to buy with
    /// @return token The address of the created token
    /// @return received The amount of tokens received from the buy
    /// @return swapped The amount swapped for initial listing
    /// @return tokenId The NFT token ID representing ownership
    function createAndBuy(
        OpenOceanParams memory _openOceanParams,
        ITokenLaunchpad.CreateParams memory _params,
        address _expected,
        uint256 _amount
    )
        external
        payable
        returns (
            address token,
            uint256 received,
            uint256 swapped,
            uint256 tokenId
        );

    /// @notice Buys a token with exact input using OpenOcean
    /// @param _openOceanParams The parameters for the OpenOcean swap
    /// @param _tokenOut The token to receive
    /// @param _minAmountOut The minimum amount of tokens to receive
    /// @param _sqrtPriceLimitX96 The price limit for the swap (0 = no limit)
    /// @return amountOut The amount of tokens received
    function buyWithExactInputWithOpenOcean(
        OpenOceanParams memory _openOceanParams,
        IERC20 _tokenOut,
        uint256 _minAmountOut,
        uint160 _sqrtPriceLimitX96
    ) external payable returns (uint256 amountOut);

    /// @notice Sells a token with exact input using OpenOcean
    /// @param _openOceanParams The parameters for the OpenOcean swap
    /// @param _tokenIn The token to sell
    /// @param _amountToSell The amount of tokens to sell
    /// @param _sqrtPriceLimitX96 The price limit for the swap (0 = no limit)
    /// @return amountSwapOut The amount received from the swap
    function sellWithExactInputWithOpenOcean(
        OpenOceanParams memory _openOceanParams,
        IERC20 _tokenIn,
        uint256 _amountToSell,
        uint160 _sqrtPriceLimitX96
    ) external payable returns (uint256 amountSwapOut);
}
