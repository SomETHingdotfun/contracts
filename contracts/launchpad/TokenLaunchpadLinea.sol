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

import {IERC20, TokenLaunchpad} from "contracts/launchpad/TokenLaunchpad.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenLaunchpadLinea is TokenLaunchpad {
  using SafeERC20 for IERC20;

  function _distributeFees(address _token0, address, address _token1, uint256 _amount0, uint256 _amount1)
    internal
    override
  {
    address etherxTreasury = 0xF0FfFD0292dE675e865A9b506bd2c434e0813d74;
    address somethingTreasury = 0x8EfeFDBe3f3f7D48b103CD220d634CBF1d0Ae1a6;

    // 20% to the etherx treasury
    // 80% to the something treasury

    IERC20(_token0).safeTransfer(etherxTreasury, _amount0 * 20 / 100);
    IERC20(_token0).safeTransfer(somethingTreasury, _amount0 * 80 / 100);

    IERC20(_token1).safeTransfer(etherxTreasury, _amount1 * 20 / 100);
    IERC20(_token1).safeTransfer(somethingTreasury, _amount1 * 80 / 100);
  }
}
