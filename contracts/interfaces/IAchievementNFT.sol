// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @title IAchievementNFT
 * @dev Interface for the AchievementNFT contract
 */
interface IAchievementNFT {
  /**
   * @dev Achievement data structure
   */
  struct Achievement {
    address token;
    bytes32 campaignId;
    uint256 score;
    string title;
    string description;
  }

  /**
   * @dev Emitted when a new minter is toggled
   */
  event MinterToggled(address indexed minter, bool isMinter);

  /**
   * @dev Emitted when an achievement is minted
   */
  event AchievementMinted(
    address indexed user,
    uint256 indexed tokenId,
    address token,
    bytes32 campaignId,
    uint256 score,
    string title,
    string description
  );

  /**
   * @dev Adds a new minter address
   * @param minter The address to add as a minter
   */
  function toggleMinter(address minter) external;

  /**
   * @dev Mints a new achievement NFT to the specified user address
   * @param achievement The achievement details
   * @param signature The signature of the minter
   * @return tokenId The minted token ID
   */
  function mint(Achievement memory achievement, bytes memory signature) external returns (uint256);
}
