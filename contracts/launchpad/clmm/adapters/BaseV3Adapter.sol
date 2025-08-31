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

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ICLMMAdapter, IClPool} from "contracts/interfaces/ICLMMAdapter.sol";

import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {ICLSwapRouter} from "contracts/interfaces/thirdparty/ICLSwapRouter.sol";
import {IClPoolFactory} from "contracts/interfaces/thirdparty/IClPoolFactory.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract BaseV3Adapter is ICLMMAdapter, Initializable {
  using SafeERC20 for IERC20;

  int24 public immutable TICK_SPACING = 200;

  uint256 public immutable GRADUATION_AMOUNT = 600_000_000 * 1e18;
  uint256 public immutable POST_GRADUATION_AMOUNT = 400_000_000 * 1e18;

  address internal _me;
  address public launchpad;
  IClPoolFactory public clPoolFactory;
  ICLSwapRouter public swapRouter;
  IERC721 public nftPositionManager;

  mapping(IERC20 token => mapping(uint256 index => uint256 lockId)) public tokenToLockId;
  mapping(IERC20 token => mapping(uint256 index => uint256 claimedFees)) public tokenToClaimedFees;

  function __BaseV3Adapter_init(
    address _launchpad,
    address _swapRouter,
    address _nftPositionManager,
    address _clPoolFactory
  ) internal {
    _me = address(this);

    clPoolFactory = IClPoolFactory(_clPoolFactory);
    launchpad = _launchpad;
    nftPositionManager = IERC721(_nftPositionManager);
    swapRouter = ICLSwapRouter(_swapRouter);
  }

  /// @inheritdoc ICLMMAdapter
  function swapWithExactOutput(IERC20 _tokenIn, IERC20 _tokenOut, uint256 _amountOut, uint256 _maxAmountIn)
    external
    virtual
    returns (uint256 amountIn)
  {
    _tokenIn.safeTransferFrom(msg.sender, address(this), _maxAmountIn);
    _tokenIn.approve(address(swapRouter), type(uint256).max);
    amountIn = swapRouter.exactOutputSingle(
      ICLSwapRouter.ExactOutputSingleParams({
        tokenIn: address(_tokenIn),
        tokenOut: address(_tokenOut),
        amountOut: _amountOut,
        recipient: msg.sender,
        deadline: block.timestamp,
        tickSpacing: TICK_SPACING,
        amountInMaximum: _maxAmountIn,
        sqrtPriceLimitX96: 0
      })
    );
    _refundTokens(_tokenIn);
  }

  /// @inheritdoc ICLMMAdapter
  function swapWithExactInput(IERC20 _tokenIn, IERC20 _tokenOut, uint256 _amountIn, uint256 _minAmountOut)
    external
    virtual
    returns (uint256 amountOut)
  {
    _tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);
    _tokenIn.approve(address(swapRouter), type(uint256).max);

    amountOut = swapRouter.exactInputSingle(
      ICLSwapRouter.ExactInputSingleParams({
        tokenIn: address(_tokenIn),
        tokenOut: address(_tokenOut),
        amountIn: _amountIn,
        recipient: msg.sender,
        deadline: block.timestamp,
        tickSpacing: TICK_SPACING,
        amountOutMinimum: _minAmountOut,
        sqrtPriceLimitX96: 0
      })
    );
  }

  /// @inheritdoc ICLMMAdapter
  function addSingleSidedLiquidity(AddLiquidityParams memory _params) external returns (address) {
    require(msg.sender == launchpad, "!launchpad");

    uint160 sqrtPriceX96Launch = TickMath.getSqrtPriceAtTick(_params.tick0 - 1);

    IClPool pool = _createPool(_params.tokenBase, _params.tokenQuote, TICK_SPACING, sqrtPriceX96Launch);

    uint256 tokenId0 =
      _mint(_params.tokenBase, _params.tokenQuote, _params.tick0, _params.tick1, TICK_SPACING, GRADUATION_AMOUNT);
    uint256 tokenId1 =
      _mint(_params.tokenBase, _params.tokenQuote, _params.tick1, _params.tick2, TICK_SPACING, POST_GRADUATION_AMOUNT);

    tokenToLockId[IERC20(_params.tokenBase)][0] = tokenId0;
    tokenToLockId[IERC20(_params.tokenBase)][1] = tokenId1;

    return address(pool);
  }

  /// @inheritdoc ICLMMAdapter
  function claimFees(address _token) external returns (uint256 fee0, uint256 fee1) {
    require(msg.sender == launchpad, "!launchpad");

    uint256 lockId0 = tokenToLockId[IERC20(_token)][0];
    uint256 lockId1 = tokenToLockId[IERC20(_token)][1];

    (uint256 fee00, uint256 fee01) = _collectFees(lockId0);
    (uint256 fee10, uint256 fee11) = _collectFees(lockId1);

    fee0 = fee00 + fee10;
    fee1 = fee01 + fee11;

    tokenToClaimedFees[IERC20(_token)][0] += fee0;
    tokenToClaimedFees[IERC20(_token)][1] += fee1;

    IERC20 quoteToken = ITokenLaunchpad(launchpad).fundingToken();
    IERC20(_token).transfer(msg.sender, fee0);
    quoteToken.transfer(msg.sender, fee1);
  }

  function claimedFees(address _token) external view returns (uint256 fee0, uint256 fee1) {
    fee0 = tokenToClaimedFees[IERC20(_token)][0];
    fee1 = tokenToClaimedFees[IERC20(_token)][1];
  }

  /// @dev Refund tokens to the owner
  /// @param _token The token to refund
  function _refundTokens(IERC20 _token) internal {
    uint256 remaining = _token.balanceOf(address(this));
    if (remaining == 0) return;
    _token.safeTransfer(msg.sender, remaining);
  }

  /// @dev Mint a position and lock it forever
  /// @param _token0 The token to mint the position for
  /// @param _token1 The token to mint the position for
  /// @param _tick0 The lower tick of the position
  /// @param _tick1 The upper tick of the position
  /// @param _tickSpacing The tick spacing of the pool
  /// @param _amount0 The amount of tokens to mint the position for
  function _mint(IERC20 _token0, IERC20 _token1, int24 _tick0, int24 _tick1, int24 _tickSpacing, uint256 _amount0)
    internal
    virtual
    returns (uint256 tokenId);

  function _collectFees(uint256 _lockId) internal virtual returns (uint256 fee0, uint256 fee1);

  /// @dev Create a pool
  /// @param _token0 The token to create the pool for
  /// @param _token1 The token to create the pool for
  /// @param _tickSpacing The tick spacing of the pool
  /// @param _sqrtPriceX96Launch The sqrt price of the pool
  /// @return pool The address of the pool
  function _createPool(IERC20 _token0, IERC20 _token1, int24 _tickSpacing, uint160 _sqrtPriceX96Launch)
    internal
    virtual
    returns (IClPool pool);

  receive() external payable {}
}
