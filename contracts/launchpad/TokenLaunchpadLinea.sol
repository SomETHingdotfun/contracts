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

contract TokenLaunchpadLinea is TokenLaunchpad {
  function _distributeFees(address _token0, address, address _token1, uint256 _amount0, uint256 _amount1)
    internal
    override
  {
    address etherxTreasury = 0x8EfeFDBe3f3f7D48b103CD220d634CBF1d0Ae1a6;
    address somethingTreasury = 0x8EfeFDBe3f3f7D48b103CD220d634CBF1d0Ae1a6;

    // 20% to the etherx treasury
    // 40% to the something treasury

    IERC20(_token0).transfer(etherxTreasury, _amount0 * 20 / 100);
    IERC20(_token0).transfer(somethingTreasury, _amount0 * 80 / 100);

    IERC20(_token1).transfer(etherxTreasury, _amount1 * 20 / 100);
    IERC20(_token1).transfer(somethingTreasury, _amount1 * 80 / 100);
  }
}
