// SPDX-License-Identifier: GPL-3.0-or-later

// ██╗      ██████╗  ██████╗██╗  ██╗███████╗██████╗     ██╗███╗   ██╗
// ██║     ██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗    ██║████╗  ██║
// ██║     ██║   ██║██║     █████╔╝ █████╗  ██║  ██║    ██║██╔██╗ ██║
// ██║     ██║   ██║██║     ██╔═██╗ ██╔══╝  ██║  ██║    ██║██║╚██╗██║
// ███████╗╚██████╔╝╚██████╗██║  ██╗███████╗██████╔╝    ██║██║ ╚████║
// ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═════╝     ╚═╝╚═╝  ╚═══╝

// Website: https://freelplocker.com
// Twitter: https://x.com/vezuresxyz

pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "contracts/interfaces/thirdparty/INonfungiblePositionManager.sol";

/**
 * @title IFreeUniV3LPLocker
 * @notice Interface for locking Uniswap V3 LP positions
 */
interface IFreeUniV3LPLocker is IERC721Receiver {
  struct LockInfo {
    uint256 lockId;
    INonfungiblePositionManager nftPositionManager;
    address pendingOwner;
    address owner;
    address collector;
    address pool;
    uint256 nftId;
    uint256 startTime;
    uint256 endTime;
  }

  /**
   * @notice Returns the next available lock ID
   * @return The next lock ID
   */
  function nextLockId() external view returns (uint256);

  /**
   * @notice Returns all lock IDs owned by a user
   * @param user The address of the user
   * @return lockIds An array of lock IDs
   */
  function getUserLocks(address user) external view returns (uint256[] memory lockIds);

  /**
   * @notice Transfers a lock to a new owner
   * @param lockId_ The ID of the lock to transfer
   * @param newOwner_ The address of the new owner
   */
  function transferLock(uint256 lockId_, address newOwner_) external;

  /**
   * @notice Accepts a lock transfer
   * @param lockId_ The ID of the lock to accept
   */
  function acceptLock(uint256 lockId_) external;

  /**
   * @notice Increases liquidity in a locked position
   * @param lockId_ The ID of the lock
   * @param params The parameters for increasing liquidity
   * @return liquidity The amount of liquidity added
   * @return amount0 The amount of token0 added
   * @return amount1 The amount of token1 added
   */
  function increaseLiquidity(uint256 lockId_, INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
    external
    payable
    returns (uint128 liquidity, uint256 amount0, uint256 amount1);

  /**
   * @notice Decreases liquidity in a locked position
   * @param lockId_ The ID of the lock
   * @param params The parameters for decreasing liquidity
   * @return amount0 The amount of token0 received
   * @return amount1 The amount of token1 received
   */
  function decreaseLiquidity(uint256 lockId_, INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1);

  /**
   * @notice Unlocks a position after the lock period has ended
   * @param lockId_ The ID of the lock to unlock
   */
  function unlock(uint256 lockId_) external;

  /**
   * @notice Extends the lock period of a position
   * @param lockId_ The ID of the lock
   * @param endTime_ The new end time for the lock
   */
  function relock(uint256 lockId_, uint256 endTime_) external;

  /**
   * @notice Collects fees from a locked position
   * @param lockId_ The ID of the lock
   * @param recipient_ The address to receive the fees
   * @param amount0Max_ The maximum amount of token0 to collect
   * @param amount1Max_ The maximum amount of token1 to collect
   * @return amount0 The amount of token0 collected
   * @return amount1 The amount of token1 collected
   */
  function collect(uint256 lockId_, address recipient_, uint128 amount0Max_, uint128 amount1Max_)
    external
    returns (uint256 amount0, uint256 amount1);

  /**
   * @notice Sets the address that can collect fees from a locked position
   * @param lockId_ The ID of the lock
   * @param collector_ The address that can collect fees
   */
  function setCollectAddress(uint256 lockId_, address collector_) external;

  event OnLock(uint256 indexed lockId, address nftPositionManager, address owner, uint256 nftId, uint256 endTime);
  event OnUnlock(uint256 indexed lockId, address owner, uint256 nftId, uint256 unlockedTime);
  event OnLockPendingTransfer(uint256 indexed lockId, address previousOwner, address newOwner);
  event OnLockTransferred(uint256 indexed lockId, address previousOwner, address newOwner);
  event OnIncreaseLiquidity(uint256 indexed lockId);
  event OnDecreaseLiquidity(uint256 indexed lockId);
  event OnRelock(uint256 indexed lockId, uint256 endTime);
  event OnSetCollector(uint256 indexed lockId, address collector);
}
