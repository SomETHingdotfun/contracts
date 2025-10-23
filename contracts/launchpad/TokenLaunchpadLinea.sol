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

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, TokenLaunchpad} from "contracts/launchpad/TokenLaunchpad.sol";

contract TokenLaunchpadLinea is TokenLaunchpad {
  using SafeERC20 for IERC20;

  function _distributeFees(address _token0, address _owner, address _token1, uint256 _amount0, uint256 _amount1)
    internal
    override
  {
    // In production, these addresses will be set. for now we're keeping it as 0x1 and 0x2
    address referralContract = 0x0000000000000000000000000000000000000001;
    address somethingTreasury = 0x0000000000000000000000000000000000000002;

    IERC20(_token0).safeTransfer(referralContract, _amount0 * 15 / 100);
    IERC20(_token0).safeTransfer(somethingTreasury, _amount0 * 50 / 100);
    IERC20(_token0).safeTransfer(_owner, _amount0 * 35 / 100);

    IERC20(_token1).safeTransfer(referralContract, _amount1 * 15 / 100);
    IERC20(_token1).safeTransfer(somethingTreasury, _amount1 * 50 / 100);
    IERC20(_token1).safeTransfer(_owner, _amount1 * 35 / 100);
  }
}
