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

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {SomeToken} from "contracts/SomeToken.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {SafeApproval} from "contracts/utils/SafeApproval.sol";

abstract contract TokenLaunchpad is
  ITokenLaunchpad,
  OwnableUpgradeable,
  ERC721EnumerableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20 for IERC20;

  ICLMMAdapter public adapter;
  IERC20[] public tokens;
  IERC20 public fundingToken;
  address public cron;

  mapping(IERC20 => uint256) public tokenToNftId;
  mapping(IERC20 => mapping(ICLMMAdapter => ValueParams)) public defaultValueParams;

  int24 public launchTick;
  int24 public graduationTick;
  int24 public upperMaxTick;

  // Constants for liquidity amounts (matching BaseV3Adapter)
  uint256 public constant GRADUATION_AMOUNT = 600_000_000 * 1e18;
  uint256 public constant POST_GRADUATION_AMOUNT = 400_000_000 * 1e18;

  receive() external payable {}

  constructor() {
    _disableInitializers();
  }

  /// @inheritdoc ITokenLaunchpad
  function initialize(address _owner, address _fundingToken, address _adapter) external initializer {
    fundingToken = IERC20(_fundingToken);
    adapter = ICLMMAdapter(_adapter);
    cron = _owner;
    __Ownable_init(_owner);
    __ERC721_init("Something.fun", "somETHing");
    __ReentrancyGuard_init();
  }

  function computeTokenAddress(CreateParams memory p, address _fundingToken, address _caller) external view returns (address, bool) {
    bytes32 salt = keccak256(abi.encode(p.salt, _caller, p.name, p.symbol));
    bytes memory bytecode = abi.encodePacked(
      type(SomeToken).creationCode,
      abi.encode(p.name, p.symbol)
    );
    bytes32 bytecodeHash = keccak256(bytecode);
    address computedAddress = Create2.computeAddress(salt, bytecodeHash, address(this));
    return (computedAddress, computedAddress < _fundingToken);
  }

  /// @inheritdoc ITokenLaunchpad
  function createAndBuy(CreateParams memory p, address expected, uint256 amount)
    external
    payable
    nonReentrant
    returns (address, uint256, uint256, uint256)
  {
    SomeToken token;

    {
      //Deploy using CREATE2
      bytes32 salt = keccak256(abi.encode(p.salt, msg.sender, p.name, p.symbol));
      bytes memory bytecode = abi.encodePacked(
        type(SomeToken).creationCode,
        abi.encode(p.name, p.symbol)
      );
      address tokenAddress = Create2.deploy(0, salt, bytecode);
      token = SomeToken(tokenAddress);
      
      if (expected != address(0) && address(token) != expected) revert InvalidTokenAddress();

      tokenToNftId[token] = tokens.length;
      tokens.push(token);

      IERC20(address(token)).forceApprove(address(adapter), type(uint256).max);
      address pool = adapter.addSingleSidedLiquidity(
        ICLMMAdapter.AddLiquidityParams({
          tokenBase: token,
          tokenQuote: fundingToken,
          tick0: launchTick,
          tick1: graduationTick,
          tick2: upperMaxTick
        })
      );
      
      emit TokenLaunched(token, address(adapter), pool, p);
    }

    _safeMint(msg.sender, tokenToNftId[token]);

    // Calculate total amount needed (1e18 bootstrap + user amount)
    // Note: funding token is always 18 decimals
    uint256 totalSwapAmount = 1e18 + amount;
    
    // Pull all required funds from caller first (fixes unfunded bootstrap issue)
    fundingToken.transferFrom(msg.sender, address(this), totalSwapAmount);
    
    // Use safe approval pattern for funding token swaps
    SafeApproval.safeApprove(fundingToken, address(adapter), totalSwapAmount);

    // buy 1 token to register the token on tools like dexscreener
    uint256 swapped = adapter.swapWithExactInput(fundingToken, token, 1 ether, 0, 0);

    // if the user wants to buy more tokens, they can do so
    uint256 received;
    if (amount > 0) {
      received = adapter.swapWithExactInput(fundingToken, token, amount, 0);
    }

    // refund any remaining tokens
    _refundTokens(token);

    return (address(token), received, swapped, tokenToNftId[token]);
  }

  /// @inheritdoc ITokenLaunchpad
  function getTotalTokens() external view returns (uint256) {
    return tokens.length;
  }

  function setLaunchTicks(int24 _launchTick, int24 _graduationTick, int24 _upperMaxTick) external {
    if (msg.sender != cron && msg.sender != owner()) revert Unauthorized();
    _updateLaunchTicks(_launchTick, _graduationTick, _upperMaxTick);
  }

  function setCron(address _cron) external onlyOwner {
    cron = _cron;
    emit CronUpdated(_cron);
  }


  /// @inheritdoc ITokenLaunchpad
  function claimFees(IERC20 _token) external nonReentrant {
    address token1 = address(fundingToken);
    (uint256 fee0, uint256 fee1) = adapter.claimFees(address(_token));

    _distributeFees(address(_token), ownerOf(tokenToNftId[_token]), token1, fee0, fee1);

    emit FeeClaimed(_token, fee0, fee1);
  }

  function claimedFees(IERC20 _token) external view returns (uint256 fee0, uint256 fee1) {
    (fee0, fee1) = adapter.claimedFees(address(_token));
  }

  /// @dev Distribute fees to the owner
  /// @param _token0 The token to distribute fees from
  /// @param _owner The owner of the token
  /// @param _token1 The token to distribute fees to
  /// @param _amount0 The amount of fees to distribute from token0
  /// @param _amount1 The amount of fees to distribute from token1
  function _distributeFees(address _token0, address _owner, address _token1, uint256 _amount0, uint256 _amount1)
    internal
    virtual;

  /// @dev Refund tokens to the owner
  /// @param _token The token to refund
  function _refundTokens(IERC20 _token) internal {
    uint256 remaining = _token.balanceOf(address(this));
    if (remaining == 0) return;
    _token.safeTransfer(msg.sender, remaining);
  }

  function _updateLaunchTicks(int24 _launchTick, int24 _graduationTick, int24 _upperMaxTick) internal {
    _validateTicks(_launchTick, _graduationTick, _upperMaxTick);
    launchTick = _launchTick;
    graduationTick = _graduationTick;
    upperMaxTick = _upperMaxTick;
    emit LaunchTicksUpdated(_launchTick, _graduationTick, _upperMaxTick);
  }

  /// @dev Validates tick parameters for proper ordering, alignment, and bounds
  /// @param _launchTick The launch tick
  /// @param _graduationTick The graduation tick  
  /// @param _upperMaxTick The upper max tick
  function _validateTicks(int24 _launchTick, int24 _graduationTick, int24 _upperMaxTick) internal pure {
    // Constants for validation
    int24 TICK_SPACING = 200;
    int24 MIN_TICK = TickMath.MIN_TICK;
    int24 MAX_TICK = TickMath.MAX_TICK;
    
    // Check ordering: launchTick < graduationTick < upperMaxTick
    if (_launchTick >= _graduationTick) {
      revert("Invalid tick ordering: launchTick must be < graduationTick");
    }
    if (_graduationTick >= _upperMaxTick) {
      revert("Invalid tick ordering: graduationTick must be < upperMaxTick");
    }
    
    // Check bounds: all ticks must be within valid range
    if (_launchTick <= MIN_TICK) {
      revert("Invalid tick bounds: launchTick must be > MIN_TICK");
    }
    if (_upperMaxTick >= MAX_TICK) {
      revert("Invalid tick bounds: upperMaxTick must be < MAX_TICK");
    }
    
    // Check alignment: all ticks must be aligned to TICK_SPACING
    if (_launchTick % TICK_SPACING != 0) {
      revert("Invalid tick alignment: launchTick must be aligned to TICK_SPACING");
    }
    if (_graduationTick % TICK_SPACING != 0) {
      revert("Invalid tick alignment: graduationTick must be aligned to TICK_SPACING");
    }
    if (_upperMaxTick % TICK_SPACING != 0) {
      revert("Invalid tick alignment: upperMaxTick must be aligned to TICK_SPACING");
    }
  }
}
