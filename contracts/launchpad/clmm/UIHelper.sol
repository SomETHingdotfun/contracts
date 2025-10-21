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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {IUIHelper} from "contracts/interfaces/IUIHelper.sol";
import {IOpenOceanCaller, IOpenOceanExchange} from "contracts/interfaces/thirdparty/IOpenOcean.sol";

contract UIHelper is IUIHelper, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    IWETH9 public immutable weth;
    IOpenOceanExchange public immutable openOcean;
    ITokenLaunchpad public immutable launchpad;
    ICLMMAdapter public immutable adapter;
    IERC20 public immutable fundingToken;

    receive() external payable {}

    constructor(address _weth, address _openocean, address _launchpad) {
        weth = IWETH9(_weth);
        openOcean = IOpenOceanExchange(_openocean);
        launchpad = ITokenLaunchpad(_launchpad);
        adapter = ICLMMAdapter(launchpad.adapter());
        fundingToken = IERC20(launchpad.fundingToken());
        fundingToken.forceApprove(address(adapter), type(uint256).max);
        fundingToken.forceApprove(address(launchpad), type(uint256).max);
    }

    function makeCalls(
        CallDescription[] memory desc
    ) external payable override {
        require(msg.sender == address(openOcean), "Only router can call");
        for (uint256 i = 0; i < desc.length; i++) {
            (bool success, ) = address(uint160(desc[i].target)).call{
                gas: desc[i].gasLimit,
                value: desc[i].value
            }(desc[i].data);
            require(success, "subcall failed");
        }
    }

    /// @inheritdoc IUIHelper
    function createAndBuy(
        OpenOceanParams memory _openOceanParams,
        ITokenLaunchpad.CreateParams memory _params,
        address _expected,
        uint256 _amount
    )
        external
        payable
        override
        nonReentrant
        returns (
            address token,
            uint256 received,
            uint256 swapped,
            uint256 tokenId
        )
    {
        // Track initial balances to prevent draining pre-existing tokens
        InitialBalances memory initialBalances = InitialBalances({
            tokenIn: address(_openOceanParams.tokenIn) == address(0)
                ? 0
                : _openOceanParams.tokenIn.balanceOf(address(this)),
            openOceanTokenIn: address(_openOceanParams.tokenIn) == address(0)
                ? 0
                : _openOceanParams.tokenIn.balanceOf(address(this)),
            openOceanTokenOut: address(_openOceanParams.tokenOut) == address(0)
                ? 0
                : _openOceanParams.tokenOut.balanceOf(address(this)),
            fundingToken: fundingToken.balanceOf(address(this)),
            tokenOut: 0
        });

        _performOpenOceanSwap(_openOceanParams);

        (token, received, swapped, tokenId) = launchpad.createAndBuy(
            _params,
            _expected,
            _amount
        );

        // send the nft to the user
        launchpad.safeTransferFrom(address(this), msg.sender, tokenId);

        _purgeAll(_openOceanParams, IERC20(token), initialBalances);
    }

    /// @inheritdoc IUIHelper
    function buyWithExactInputWithOpenOcean(
        OpenOceanParams memory _openOceanParams,
        IERC20 _tokenOut,
        uint256 _minAmountOut,
        uint160 _sqrtPriceLimitX96
    ) external payable override nonReentrant returns (uint256 amountOut) {
        // Track initial balances to prevent draining pre-existing tokens
        InitialBalances memory initialBalances = InitialBalances({
            tokenIn: address(_openOceanParams.tokenIn) == address(0)
                ? 0
                : _openOceanParams.tokenIn.balanceOf(address(this)),
            openOceanTokenIn: address(_openOceanParams.tokenIn) == address(0)
                ? 0
                : _openOceanParams.tokenIn.balanceOf(address(this)),
            openOceanTokenOut: address(_openOceanParams.tokenOut) == address(0)
                ? 0
                : _openOceanParams.tokenOut.balanceOf(address(this)),
            fundingToken: fundingToken.balanceOf(address(this)),
            tokenOut: _tokenOut.balanceOf(address(this))
        });

        _performOpenOceanSwap(_openOceanParams);

        // we now have fundingToken; We swap it for the token out
        uint256 _amountIn = fundingToken.balanceOf(address(this));
        if (_amountIn == 0) revert NoFundingTokensReceived();
        amountOut = adapter.swapWithExactInput(
            fundingToken,
            _tokenOut,
            _amountIn,
            _minAmountOut,
            _sqrtPriceLimitX96
        );

        // send everything back & collect fees
        _purgeAll(_openOceanParams, _tokenOut, initialBalances);
        launchpad.claimFees(_tokenOut);
    }

    /// @inheritdoc IUIHelper
    function sellWithExactInputWithOpenOcean(
        OpenOceanParams memory _openOceanParams,
        IERC20 _tokenIn,
        uint256 _amountToSell,
        uint160 _sqrtPriceLimitX96
    ) external payable override nonReentrant returns (uint256 amountSwapOut) {
        // Track initial balances to prevent draining pre-existing tokens
        InitialBalances memory initialBalances = InitialBalances({
            tokenIn: address(_openOceanParams.tokenIn) == address(0)
                ? 0
                : _openOceanParams.tokenIn.balanceOf(address(this)),
            openOceanTokenIn: address(_openOceanParams.tokenIn) == address(0)
                ? 0
                : _openOceanParams.tokenIn.balanceOf(address(this)),
            openOceanTokenOut: address(_openOceanParams.tokenOut) == address(0)
                ? 0
                : _openOceanParams.tokenOut.balanceOf(address(this)),
            fundingToken: fundingToken.balanceOf(address(this)),
            tokenOut: _tokenIn.balanceOf(address(this))
        });

        _tokenIn.safeTransferFrom(msg.sender, address(this), _amountToSell);
        _tokenIn.forceApprove(address(adapter), type(uint256).max);

        // we now have token; we sell it for fundingToken
        amountSwapOut = adapter.swapWithExactInput(
            _tokenIn,
            fundingToken,
            _amountToSell,
            _openOceanParams.tokenAmountIn,
            _sqrtPriceLimitX96
        );

        // if needed we zap the fundingToken for any other token
        if (_openOceanParams.calls.length > 0) {
            if (address(_openOceanParams.tokenIn) != address(fundingToken))
                revert InvalidTokenIn();
            if (_openOceanParams.tokenAmountIn != 0)
                revert TokenAmountInMustBeZero();
            _performOpenOceanSwap(_openOceanParams);
        }

        // send everything back & collect fees
        _purgeAll(_openOceanParams, _tokenIn, initialBalances);
        launchpad.claimFees(_tokenIn);
    }

    /// @notice Purges all tokens from the contract
    /// @param openOceanParams The parameters for the swap
    /// @param _tokenOut The token output
    /// @param initialBalances The initial balances before the transaction
    function _purgeAll(
        OpenOceanParams memory openOceanParams,
        IERC20 _tokenOut,
        InitialBalances memory initialBalances
    ) internal {
        _purge(
            address(openOceanParams.tokenIn),
            initialBalances.openOceanTokenIn
        );
        _purge(
            address(openOceanParams.tokenOut),
            initialBalances.openOceanTokenOut
        );
        _purge(address(fundingToken), initialBalances.fundingToken);
        _purge(address(_tokenOut), initialBalances.tokenOut);
    }

    /// @notice Purges the given token
    /// @param token The token to purge
    /// @param initialBalance The initial balance of the token before the transaction
    function _purge(address token, uint256 initialBalance) internal {
        if (token == address(0)) {
            if (address(this).balance > initialBalance) {
                (bool success, ) = msg.sender.call{
                    value: address(this).balance - initialBalance
                }("");
                if (!success) revert ETHTransferFailed();
            }
        } else {
            uint256 currentBalance = IERC20(token).balanceOf(address(this));
            if (currentBalance > initialBalance) {
                IERC20(token).safeTransfer(
                    msg.sender,
                    currentBalance - initialBalance
                );
            }
        }
    }

    /// @notice Performs OpenOcean swap
    /// @param params The parameters for the swap
    function _performOpenOceanSwap(OpenOceanParams memory params) internal {
        // Handle input token transfers and approvals
        if (address(params.tokenIn) == address(0)) {
            if (msg.value != params.tokenAmountIn) revert InvalidETHAmount();
        } else if (params.tokenAmountIn > 0) {
            params.tokenIn.safeTransferFrom(
                msg.sender,
                address(this),
                params.tokenAmountIn
            );
            params.tokenIn.forceApprove(address(openOcean), type(uint256).max);
        }

        // Only perform swap if there are calls to execute
        if (params.calls.length > 0) {
            IOpenOceanExchange.SwapDescription
                memory swapDesc = IOpenOceanExchange.SwapDescription({
                    srcToken: params.tokenIn,
                    dstToken: params.tokenOut,
                    srcReceiver: address(this), // Contract receives the tokens first
                    dstReceiver: address(this), // Contract receives the output tokens
                    amount: params.tokenAmountIn,
                    minReturnAmount: params.minReturnAmount,
                    guaranteedAmount: params.guaranteedAmount,
                    flags: params.flags,
                    referrer: params.referrer,
                    permit: params.permit
                });

            // Execute the swap and handle aggregator reverts
            uint256 returnAmount;
            try
                openOcean.swap{value: msg.value}(
                    IOpenOceanCaller(address(this)),
                    swapDesc,
                    params.calls
                )
            returns (uint256 _returnAmount) {
                returnAmount = _returnAmount;
            } catch {
                revert OpenOceanCallFailed();
            }

            if (returnAmount < params.minReturnAmount) {
                revert InsufficientOutputAmount(
                    returnAmount,
                    params.minReturnAmount
                );
            }
        }
    }

    /// @notice Required implementation for IERC721Receiver to receive ERC721 tokens
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
