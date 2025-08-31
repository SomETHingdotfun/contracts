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

import {BaseV3Adapter, IClPool, IERC20, SafeERC20} from "./BaseV3Adapter.sol";

interface INonfungiblePositionManagerRamses {
  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  struct MintParams {
    address token0;
    address token1;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
  }

  function mint(MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

  function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

interface IRamsesPoolFactory {
  function createPool(IERC20 _token0, IERC20 _token1, int24 _tickSpacing, uint160 _sqrtPriceX96Launch)
    external
    returns (address pool);
}

contract RamsesAdapter is BaseV3Adapter {
  using SafeERC20 for IERC20;

  function initialize(address _launchpad, address _swapRouter, address _nftPositionManager, address _clPoolFactory)
    external
    initializer
  {
    __BaseV3Adapter_init(_launchpad, _swapRouter, _nftPositionManager, _clPoolFactory);
  }

  function _mint(IERC20 _token0, IERC20 _token1, int24 _tick0, int24 _tick1, int24 _tickSpacing, uint256 _amount0)
    internal
    override
    returns (uint256 tokenId)
  {
    _token0.safeTransferFrom(msg.sender, address(this), _amount0);
    _token0.approve(address(nftPositionManager), _amount0);

    // mint the position
    INonfungiblePositionManagerRamses.MintParams memory params = INonfungiblePositionManagerRamses.MintParams({
      token0: address(_token0),
      token1: address(_token1),
      tickSpacing: _tickSpacing,
      tickLower: _tick0,
      tickUpper: _tick1,
      amount0Desired: _amount0,
      amount1Desired: 0,
      amount0Min: 0,
      amount1Min: 0,
      recipient: _me,
      deadline: block.timestamp
    });

    (tokenId,,,) = INonfungiblePositionManagerRamses(address(nftPositionManager)).mint(params);
  }

  function _collectFees(uint256 _nftId) internal override returns (uint256 fee0, uint256 fee1) {
    (fee0, fee1) = INonfungiblePositionManagerRamses(address(nftPositionManager)).collect(
      INonfungiblePositionManagerRamses.CollectParams(_nftId, address(this), type(uint128).max, type(uint128).max)
    );
  }

  function _createPool(IERC20 _token0, IERC20 _token1, int24 _tickSpacing, uint160 _sqrtPriceX96Launch)
    internal
    virtual
    override
    returns (IClPool pool)
  {
    address _pool =
      IRamsesPoolFactory(address(clPoolFactory)).createPool(_token0, _token1, _tickSpacing, _sqrtPriceX96Launch);
    pool = IClPool(_pool);
  }
}
