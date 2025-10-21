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
interface IOpenOceanCaller {
    struct CallDescription {
        uint256 target;
        uint256 gasLimit;
        uint256 value;
        bytes data;
    }
    function makeCalls(CallDescription[] memory desc) external payable;
}

interface IOpenOceanExchange {
    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 guaranteedAmount;
        uint256 flags;
        address referrer;
        bytes permit;
    }

    function swap(
        IOpenOceanCaller caller,
        SwapDescription calldata desc,
        IOpenOceanCaller.CallDescription[] calldata calls
    ) external payable returns (uint256 returnAmount);
}
