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

interface IGoPlusLocker {
  struct FeeStruct {
    string name; // name by which the fee is accessed
    uint256 lpFee; // 100 = 1%, 10,000 = 100%
    uint256 collectFee; // 100 = 1%, 10,000 = 100%
    uint256 lockFee; // in amount tokens
    address lockFeeToken; // address(0) = ETH otherwise ERC20 address expected
  }

  struct LockInfo {
    uint256 lockId;
    address nftPositionManager;
    address pendingOwner;
    address owner;
    address collector;
    address pool;
    uint256 collectFee;
    uint256 nftId;
    uint256 startTime;
    uint256 endTime;
  }

  function fees(bytes32 nameHash) external view returns (FeeStruct memory);
  function feeReceiver() external view returns (address);
  function customFeeSigner() external view returns (address);
  function FEE_DENOMINATOR() external view returns (uint256);
  function nextLockId() external view returns (uint256);
  function locks(uint256 lockId) external view returns (LockInfo memory);
  function disabledSigs(bytes memory sig) external view returns (bool);

  function addOrUpdateFee(
    string memory name_,
    uint256 lpFee_,
    uint256 collectFee_,
    uint256 lockFee_,
    address lockFeeToken_
  ) external;

  function removeFee(string memory name_) external;
  function updateFeeReceiver(address feeReceiver_) external;
  function updateFeeSigner(address feeSigner_) external;
  function addSupportedNftManager(address nftManager_) external;
  function disableSig(bytes memory sig) external;
  function supportedNftManager(address nftManager_) external view returns (bool);
  function isSupportedFeeName(string memory name_) external view returns (bool);
  function getFee(string memory name_) external view returns (FeeStruct memory);

  function lock(
    address nftManager_,
    uint256 nftId_,
    address owner_,
    address collector_,
    uint256 endTime_,
    string memory feeName_
  ) external payable returns (uint256 lockId);

  function lockWithCustomFee(
    address nftManager_,
    uint256 nftId_,
    address owner_,
    address collector_,
    uint256 endTime_,
    bytes memory signature_,
    FeeStruct memory feeObj_
  ) external payable returns (uint256 lockId);

  function transferLock(uint256 lockId_, address newOwner_) external;
  function acceptLock(uint256 lockId_) external;
  function unlock(uint256 lockId_) external;
  function relock(uint256 lockId_, uint256 endTime_) external;
  function collect(uint256 lockId_, address recipient_, uint128 amount0Max_, uint128 amount1Max_)
    external
    returns (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1);
  function setCollectAddress(uint256 lockId_, address collector_) external;
  function adminRefundEth(uint256 amount_, address payable receiver_) external;
  function adminRefundERC20(address token_, address receiver_, uint256 amount_) external;
  function getUserLocks(address user) external view returns (uint256[] memory lockIds);
}
