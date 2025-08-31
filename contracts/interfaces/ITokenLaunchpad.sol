// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {ICLMMAdapter} from "./ICLMMAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ITokenLaunchpad Interface
/// @notice Interface for the TokenLaunchpad contract that handles token launches
interface ITokenLaunchpad {
  /// @notice Parameters required to create a new token launch
  /// @param name The name of the token
  /// @param symbol The symbol of the token
  /// @param metadata IPFS hash or other metadata about the token
  /// @param fundingToken The token used for funding the launch
  /// @param salt Random value to ensure unique deployment address
  /// @param launchTick The tick at which the token launches
  /// @param graduationTick The tick that must be reached for graduation
  /// @param upperMaxTick The maximum tick allowed
  /// @param graduationLiquidity The liquidity at graduation
  /// @param fee The fee for the token liquidity pair
  /// @param adapter The adapter used for the token launch
  struct CreateParams {
    bytes32 salt;
    string metadata;
    string name;
    string symbol;
  }

  // Contains numeric launch parameters
  struct ValueParams {
    int24 launchTick;
    int24 graduationTick;
    int24 upperMaxTick;
    uint24 fee;
    int24 tickSpacing;
    uint256 graduationLiquidity;
  }

  /// @notice Emitted when fee settings are updated
  /// @param feeDestination The address where fees will be sent
  /// @param fee The new fee amount
  event FeeUpdated(address indexed feeDestination, uint256 fee);

  /// @notice Emitted when a token is launched
  /// @param token The token that was launched
  /// @param adapter The address of the adapter used to launch the token
  /// @param pool The address of the pool for the token
  /// @param params The parameters used to launch the token
  event TokenLaunched(IERC20 indexed token, address indexed adapter, address indexed pool, CreateParams params);

  /// @notice Emitted when referral settings are updated
  /// @param referralDestination The address where referrals will be sent
  /// @param referralFee The new referral fee amount
  event ReferralUpdated(address indexed referralDestination, uint256 referralFee);

  /// @notice Emitted when tokens are allocated to the creator
  /// @param token The token that was launched
  /// @param creator The address of the creator
  /// @param amount The amount of tokens allocated to the creator
  event CreatorAllocation(IERC20 indexed token, address indexed creator, uint256 amount);

  /// @notice Emitted when the cron is updated
  /// @param newCron The new cron address
  event CronUpdated(address indexed newCron);

  /// @notice Emitted when the metadata URL is updated
  /// @param metadataUrl The new metadata URL
  event MetadataUrlUpdated(string metadataUrl);

  /// @notice Emitted when the launch ticks are updated
  /// @param _launchTick The new launch tick
  /// @param _graduationTick The new graduation tick
  /// @param _upperMaxTick The new upper max tick
  event LaunchTicksUpdated(int24 _launchTick, int24 _graduationTick, int24 _upperMaxTick);

  /// @notice Emitted when a fee is claimed for a token
  /// @param _token The token that the fee was claimed for
  /// @param _fee0 The amount of fee claimed for token0
  /// @param _fee1 The amount of fee claimed for token1
  event FeeClaimed(IERC20 indexed _token, uint256 _fee0, uint256 _fee1);

  /// @notice Initializes the launchpad contract
  /// @param _owner The owner address
  /// @param _fundingToken The funding token address
  /// @param _adapter The adapter address
  function initialize(address _owner, address _fundingToken, address _adapter) external;

  /// @notice Gets the funding token
  /// @return fundingToken The funding token
  function fundingToken() external view returns (IERC20 fundingToken);

  /// @notice Creates a new token launch
  /// @param p The parameters for the token launch
  /// @param expected The expected address where token will be deployed
  /// @param amount The amount of tokens to buy
  /// @return token The address of the newly created token
  /// @return received The amount of tokens received if the user chooses to buy at launch
  /// @return swapped The amount of tokens swapped if the user chooses to swap at launch
  function createAndBuy(CreateParams memory p, address expected, uint256 amount)
    external
    payable
    returns (address token, uint256 received, uint256 swapped);

  /// @notice Gets the adapter
  /// @return adapter The adapter
  function adapter() external view returns (ICLMMAdapter adapter);

  /// @notice Gets the total number of tokens launched
  /// @return totalTokens The total count of launched tokens
  function getTotalTokens() external view returns (uint256 totalTokens);

  /// @notice Claims accumulated fees for a specific token
  /// @param _token The token to claim fees for
  function claimFees(IERC20 _token) external;

  /// @notice Gets the claimed fees for a token
  /// @param _token The token to get the claimed fees for
  /// @return claimedFees0 The claimed fees for the token
  /// @return claimedFees1 The claimed fees for the token
  function claimedFees(IERC20 _token) external view returns (uint256 claimedFees0, uint256 claimedFees1);
}
