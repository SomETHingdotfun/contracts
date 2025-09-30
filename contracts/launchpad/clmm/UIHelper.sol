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

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";

contract UIHelper is ReentrancyGuard {
  using SafeERC20 for IERC20;

  IWETH9 public immutable weth;
  address public immutable ODOS;
  ITokenLaunchpad public immutable launchpad;
  ICLMMAdapter public immutable adapter;
  IERC20 public immutable fundingToken;

  struct OdosParams {
    IERC20 tokenIn;
    uint256 tokenAmountIn;
    IERC20 odosTokenIn;
    uint256 odosTokenAmountIn;
    uint256 minOdosTokenAmountOut;
    IERC20 odosTokenOut;
    bytes odosData;
  }

  receive() external payable {}

  constructor(address _weth, address _odos, address _launchpad) {
    weth = IWETH9(_weth);
    ODOS = _odos;
    launchpad = ITokenLaunchpad(_launchpad);
    adapter = ICLMMAdapter(launchpad.adapter());
    fundingToken = IERC20(launchpad.fundingToken());
    fundingToken.approve(address(adapter), type(uint256).max);
    fundingToken.approve(address(launchpad), type(uint256).max);
  }

  function createAndBuy(
    OdosParams memory _odosParams,
    ITokenLaunchpad.CreateParams memory _params,
    address _expected,
    uint256 _amount
  ) public payable nonReentrant returns (address token, uint256 received, uint256 swapped, uint256 tokenId) {
    _performZap(_odosParams);

    (token, received, swapped, tokenId) = launchpad.createAndBuy(_params, _expected, _amount);

    // send the nft to the user
    launchpad.safeTransferFrom(address(this), msg.sender, tokenId);

    _purgeAll(_odosParams, IERC20(token));
  }

  /// @notice Buys a token with exact input using ODOS
  /// @param _odosParams The parameters for the zap
  /// @param _tokenOut The token to receive
  /// @param _minAmountOut The minimum amount of tokens to receive
  function buyWithExactInputWithOdos(OdosParams memory _odosParams, IERC20 _tokenOut, uint256 _minAmountOut)
    public
    payable
    nonReentrant
    returns (uint256 amountOut)
  {
    _performZap(_odosParams);

    // we now have fundingToken; We swap it for the token out
    uint256 _amountIn = fundingToken.balanceOf(address(this));
    amountOut = adapter.swapWithExactInput(fundingToken, _tokenOut, _amountIn, _minAmountOut);

    // send everything back & collect fees
    _purgeAll(_odosParams, _tokenOut);
    launchpad.claimFees(_tokenOut);
  }

  /// @notice Sells a token with exact input using ODOS
  /// @param _odosParams The parameters for the zap
  /// @param _tokenIn The token to sell
  /// @param _amountToSell The amount of tokens to sell
  function sellWithExactInputWithOdos(OdosParams memory _odosParams, IERC20 _tokenIn, uint256 _amountToSell)
    public
    payable
    nonReentrant
    returns (uint256 amountSwapOut)
  {
    _tokenIn.safeTransferFrom(msg.sender, address(this), _amountToSell);
    _tokenIn.approve(address(adapter), type(uint256).max);

    // we now have token; we sell it for fundingToken
    amountSwapOut = adapter.swapWithExactInput(_tokenIn, fundingToken, _amountToSell, _odosParams.tokenAmountIn);

    // if needed we zap the fundingToken for any other token
    if (_odosParams.odosData.length > 0) {
      require(address(_odosParams.tokenIn) == address(fundingToken), "Invalid token in");
      require(_odosParams.tokenAmountIn == 0, "Token amount in is 0"); // not needed as we are selling exact input
      _performZap(_odosParams);
    }

    // send everything back & collect fees
    _purgeAll(_odosParams, _tokenIn);
    launchpad.claimFees(_tokenIn);
  }

  /// @notice Purges all tokens from the contract
  /// @param odosParams The parameters for the zap
  function _purgeAll(OdosParams memory odosParams, IERC20 _tokenOut) internal {
    _purge(address(odosParams.tokenIn));
    _purge(address(odosParams.odosTokenIn));
    _purge(address(odosParams.odosTokenOut));
    _purge(address(fundingToken));
    _purge(address(_tokenOut));
  }

  /// @notice Purges the given token
  /// @param token The token to purge
  function _purge(address token) internal {
    if (token == address(0)) {
      if (address(this).balance > 0) {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Failed to send ETH");
      }
    } else {
      uint256 balance = IERC20(token).balanceOf(address(this));
      if (balance > 0) IERC20(token).safeTransfer(msg.sender, balance);
    }
  }

  /// @notice Prepares the zap for the given token and odos data
  /// @param odosParams The parameters for the zap
  function _performZap(OdosParams memory odosParams) internal {
    if (address(odosParams.tokenIn) == address(0)) {
      require(msg.value == odosParams.tokenAmountIn, "Invalid ETH amount");
    } else if (odosParams.tokenAmountIn > 0) {
      odosParams.tokenIn.safeTransferFrom(msg.sender, address(this), odosParams.tokenAmountIn);
    }

    if (address(odosParams.tokenIn) != address(0)) {
      odosParams.tokenIn.approve(ODOS, type(uint256).max);
    }

    if (odosParams.odosData.length > 0) {
      (bool success,) = ODOS.call{value: msg.value}(odosParams.odosData);
      require(success, "Odos call failed");

      if (odosParams.minOdosTokenAmountOut > 0) {
        uint256 amountIn = odosParams.odosTokenOut.balanceOf(address(this));
        require(amountIn >= odosParams.minOdosTokenAmountOut, "!minAmountIn");
      }
    }
  }
}
