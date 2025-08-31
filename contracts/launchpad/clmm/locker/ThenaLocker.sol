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

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IGoPlusLocker} from "contracts/interfaces/IGoPlusLocker.sol";

contract ThenaLocker is IGoPlusLocker {
  using SafeERC20 for IERC20;

  // Constants
  uint256 public constant override FEE_DENOMINATOR = 10_000;

  // State variables
  mapping(bytes32 => FeeStruct) private _fees;
  address private _feeReceiver;
  address private _customFeeSigner;
  uint256 private _nextLockId;
  mapping(uint256 => LockInfo) private _locks;
  mapping(bytes => bool) private _disabledSigs;
  mapping(address => bool) private _supportedNftManagers;
  mapping(address => uint256[]) private _userLocks;

  constructor(address nftManager_) {
    _supportedNftManagers[nftManager_] = true;
  }

  // View functions
  function fees(bytes32 nameHash) external view override returns (FeeStruct memory) {
    return _fees[nameHash];
  }

  function feeReceiver() external view override returns (address) {
    return _feeReceiver;
  }

  function customFeeSigner() external view override returns (address) {
    return _customFeeSigner;
  }

  function nextLockId() external view override returns (uint256) {
    return _nextLockId;
  }

  function locks(uint256 lockId) external view override returns (LockInfo memory) {
    return _locks[lockId];
  }

  function disabledSigs(bytes memory sig) external view override returns (bool) {
    return _disabledSigs[sig];
  }

  function supportedNftManager(address nftManager_) external view override returns (bool) {
    return _supportedNftManagers[nftManager_];
  }

  function isSupportedFeeName(string memory name_) external view override returns (bool) {
    bytes32 nameHash = keccak256(bytes(name_));
    return _fees[nameHash].lpFee != 0;
  }

  function getFee(string memory name_) external view override returns (FeeStruct memory) {
    bytes32 nameHash = keccak256(bytes(name_));
    return _fees[nameHash];
  }

  function getUserLocks(address user) external view override returns (uint256[] memory) {
    return _userLocks[user];
  }

  // Admin functions
  function addOrUpdateFee(
    string memory name_,
    uint256 lpFee_,
    uint256 collectFee_,
    uint256 lockFee_,
    address lockFeeToken_
  ) external override {
    // do nothing
  }

  function removeFee(string memory name_) external override {
    // do nothing
  }

  function updateFeeReceiver(address feeReceiver_) external override {
    // do nothing
  }

  function updateFeeSigner(address) external override {
    // do nothing
  }

  function addSupportedNftManager(address) external override {
    // do nothing
  }

  function disableSig(bytes memory sig) external override {
    // do nothing
  }

  // Core functions
  function lock(
    address nftManager_,
    uint256 nftId_,
    address owner_,
    address collector_,
    uint256 endTime_,
    string memory
  ) external payable override returns (uint256 lockId) {
    require(_supportedNftManagers[nftManager_], "Unsupported NFT manager");

    IERC721(nftManager_).transferFrom(msg.sender, address(this), nftId_);

    lockId = _nextLockId++;
    _locks[lockId] = LockInfo({
      lockId: lockId,
      nftPositionManager: nftManager_,
      pendingOwner: address(0),
      owner: owner_,
      collector: collector_,
      pool: address(0), // This would need to be set based on the NFT position
      collectFee: 0,
      nftId: nftId_,
      startTime: block.timestamp,
      endTime: endTime_
    });

    _userLocks[owner_].push(lockId);
  }

  function lockWithCustomFee(
    address nftManager_,
    uint256 nftId_,
    address owner_,
    address collector_,
    uint256 endTime_,
    bytes memory signature_,
    FeeStruct memory feeObj_
  ) external payable override returns (uint256 lockId) {
    // do nothing
  }

  function transferLock(uint256, address) external override {
    // do nothing
  }

  function acceptLock(uint256) external override {
    // do nothing
  }

  function unlock(uint256) external override {
    // do nothing
  }

  function relock(uint256, uint256) external override {
    // do nothing
  }

  function collect(uint256, address, uint128, uint128)
    external
    pure
    override
    returns (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1)
  {
    // do nothing
    return (0, 0, 0, 0);
  }

  function setCollectAddress(uint256, address) external override {
    // do nothing
  }

  function adminRefundEth(uint256, address payable) external override {
    // do nothing
  }

  function adminRefundERC20(address, address, uint256) external override {
    // do nothing
  }
}
