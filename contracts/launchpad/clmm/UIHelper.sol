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

contract UIHelper is IUIHelper, ReentrancyGuard, IERC721Receiver {
  using SafeERC20 for IERC20;

  IWETH9 public immutable weth;
  address public immutable ODOS;
  ITokenLaunchpad public immutable launchpad;
  ICLMMAdapter public immutable adapter;
  IERC20 public immutable fundingToken;

  struct InitialBalances {
    uint256 tokenIn;
    uint256 odosTokenIn;
    uint256 odosTokenOut;
    uint256 fundingToken;
    uint256 tokenOut;
  }

  receive() external payable {}

  constructor(address _weth, address _odos, address _launchpad) {
    weth = IWETH9(_weth);
    ODOS = _odos;
    launchpad = ITokenLaunchpad(_launchpad);
    adapter = ICLMMAdapter(launchpad.adapter());
    fundingToken = IERC20(launchpad.fundingToken());
    fundingToken.forceApprove(address(adapter), type(uint256).max);
    fundingToken.forceApprove(address(launchpad), type(uint256).max);
  }

  /// @inheritdoc IUIHelper
  function createAndBuy(
    OdosParams memory _odosParams,
    ITokenLaunchpad.CreateParams memory _params,
    address _expected,
    uint256 _amount
  ) external payable override nonReentrant returns (address token, uint256 received, uint256 swapped, uint256 tokenId) {
    // Track initial balances to prevent draining pre-existing tokens
    InitialBalances memory initialBalances = InitialBalances({
      tokenIn: address(_odosParams.tokenIn) == address(0) ? 0 : _odosParams.tokenIn.balanceOf(address(this)),
      odosTokenIn: address(_odosParams.odosTokenIn) == address(0) ? 0 : _odosParams.odosTokenIn.balanceOf(address(this)),
      odosTokenOut: address(_odosParams.odosTokenOut) == address(0) ? 0 : _odosParams.odosTokenOut.balanceOf(address(this)),
      fundingToken: fundingToken.balanceOf(address(this)),
      tokenOut: 0
    });

    _performZap(_odosParams);

    (token, received, swapped, tokenId) = launchpad.createAndBuy(_params, _expected, _amount);

    // send the nft to the user
    launchpad.safeTransferFrom(address(this), msg.sender, tokenId);

    _purgeAll(_odosParams, IERC20(token), initialBalances);
  }

  /// @inheritdoc IUIHelper
  function buyWithExactInputWithOdos(
    OdosParams memory _odosParams,
    IERC20 _tokenOut,
    uint256 _minAmountOut,
    uint160 _sqrtPriceLimitX96
  ) external payable override nonReentrant returns (uint256 amountOut) {
    // Track initial balances to prevent draining pre-existing tokens
    InitialBalances memory initialBalances = InitialBalances({
      tokenIn: address(_odosParams.tokenIn) == address(0) ? 0 : _odosParams.tokenIn.balanceOf(address(this)),
      odosTokenIn: address(_odosParams.odosTokenIn) == address(0) ? 0 : _odosParams.odosTokenIn.balanceOf(address(this)),
      odosTokenOut: address(_odosParams.odosTokenOut) == address(0) ? 0 : _odosParams.odosTokenOut.balanceOf(address(this)),
      fundingToken: fundingToken.balanceOf(address(this)),
      tokenOut: _tokenOut.balanceOf(address(this))
    });

    _performZap(_odosParams);

    // we now have fundingToken; We swap it for the token out
    uint256 _amountIn = fundingToken.balanceOf(address(this));
    if (_amountIn == 0) revert NoFundingTokensReceived();
    amountOut = adapter.swapWithExactInput(fundingToken, _tokenOut, _amountIn, _minAmountOut, _sqrtPriceLimitX96);

    // send everything back & collect fees
    _purgeAll(_odosParams, _tokenOut, initialBalances);
    launchpad.claimFees(_tokenOut);
  }

  /// @inheritdoc IUIHelper
  function sellWithExactInputWithOdos(
    OdosParams memory _odosParams,
    IERC20 _tokenIn,
    uint256 _amountToSell,
    uint160 _sqrtPriceLimitX96
  ) external payable override nonReentrant returns (uint256 amountSwapOut) {
    // Track initial balances to prevent draining pre-existing tokens
    InitialBalances memory initialBalances = InitialBalances({
      tokenIn: address(_odosParams.tokenIn) == address(0) ? 0 : _odosParams.tokenIn.balanceOf(address(this)),
      odosTokenIn: address(_odosParams.odosTokenIn) == address(0) ? 0 : _odosParams.odosTokenIn.balanceOf(address(this)),
      odosTokenOut: address(_odosParams.odosTokenOut) == address(0) ? 0 : _odosParams.odosTokenOut.balanceOf(address(this)),
      fundingToken: fundingToken.balanceOf(address(this)),
      tokenOut: _tokenIn.balanceOf(address(this))
    });

    _tokenIn.safeTransferFrom(msg.sender, address(this), _amountToSell);
    _tokenIn.forceApprove(address(adapter), type(uint256).max);

    // we now have token; we sell it for fundingToken
    amountSwapOut = adapter.swapWithExactInput(_tokenIn, fundingToken, _amountToSell, _odosParams.tokenAmountIn, _sqrtPriceLimitX96);

    // if needed we zap the fundingToken for any other token
    if (_odosParams.odosData.length > 0) {
      if (address(_odosParams.tokenIn) != address(fundingToken)) revert InvalidTokenIn();
      if (_odosParams.tokenAmountIn != 0) revert TokenAmountInMustBeZero(); // not needed as we are selling exact input
      _performZap(_odosParams);
    }

    // send everything back & collect fees
    _purgeAll(_odosParams, _tokenIn, initialBalances);
    launchpad.claimFees(_tokenIn);
  }

  /// @notice Purges all tokens from the contract
  /// @param odosParams The parameters for the zap
  /// @param _tokenOut The token output
  /// @param initialBalances The initial balances before the transaction
  function _purgeAll(OdosParams memory odosParams, IERC20 _tokenOut, InitialBalances memory initialBalances) internal {
    _purge(address(odosParams.tokenIn), initialBalances.tokenIn);
    _purge(address(odosParams.odosTokenIn), initialBalances.odosTokenIn);
    _purge(address(odosParams.odosTokenOut), initialBalances.odosTokenOut);
    _purge(address(fundingToken), initialBalances.fundingToken);
    _purge(address(_tokenOut), initialBalances.tokenOut);
  }

  /// @notice Purges the given token
  /// @param token The token to purge
  /// @param initialBalance The initial balance of the token before the transaction
  function _purge(address token, uint256 initialBalance) internal {
    if (token == address(0)) {
      if (address(this).balance > initialBalance) {
        (bool success,) = msg.sender.call{value: address(this).balance - initialBalance}("");
        if (!success) revert ETHTransferFailed();
      }
    } else {
      uint256 currentBalance = IERC20(token).balanceOf(address(this));
      if (currentBalance > initialBalance) {
        IERC20(token).safeTransfer(msg.sender, currentBalance - initialBalance);
      }
    }
  }

  /// @notice Prepares the zap for the given token and odos data
  /// @param odosParams The parameters for the zap
  function _performZap(OdosParams memory odosParams) internal {
    if (address(odosParams.tokenIn) == address(0)) {
      if (msg.value != odosParams.tokenAmountIn) revert InvalidETHAmount();
    } else if (odosParams.tokenAmountIn > 0) {
      odosParams.tokenIn.safeTransferFrom(msg.sender, address(this), odosParams.tokenAmountIn);
    }

    if (address(odosParams.tokenIn) != address(0)) {
      odosParams.tokenIn.forceApprove(ODOS, type(uint256).max);
    }

  if (odosParams.odosData.length > 0) {
    uint256 balanceBefore = address(odosParams.odosTokenOut) == address(0) 
      ? address(this).balance 
      : odosParams.odosTokenOut.balanceOf(address(this));
    
    (bool success,) = ODOS.call{value: msg.value}(odosParams.odosData);
    if (!success) revert OdosCallFailed();

    if (odosParams.minOdosTokenAmountOut > 0) {
      uint256 balanceAfter = address(odosParams.odosTokenOut) == address(0) 
        ? address(this).balance 
        : odosParams.odosTokenOut.balanceOf(address(this));
      uint256 amountReceived = balanceAfter - balanceBefore;
      if (amountReceived < odosParams.minOdosTokenAmountOut) {
        revert InsufficientOutputAmount(amountReceived, odosParams.minOdosTokenAmountOut);
      }
    }
  }
  }

  /// @notice Required implementation for IERC721Receiver to receive ERC721 tokens
  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}
