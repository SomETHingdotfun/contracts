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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SomeToken} from "contracts/SomeToken.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";

import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";

abstract contract TokenLaunchpad is ITokenLaunchpad, OwnableUpgradeable, ERC721EnumerableUpgradeable {
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

  receive() external payable {}

  /// @inheritdoc ITokenLaunchpad
  function initialize(address _owner, address _fundingToken, address _adapter) external initializer {
    fundingToken = IERC20(_fundingToken);
    adapter = ICLMMAdapter(_adapter);
    cron = _owner;
    __Ownable_init(_owner);
    __ERC721_init("Nothing.fun", "nothing");
  }

  /// @inheritdoc ITokenLaunchpad
  function createAndBuy(CreateParams memory p, address expected, uint256 amount)
    external
    payable
    returns (address, uint256, uint256, uint256)
  {
    SomeToken token;

    {
      bytes32 salt = keccak256(abi.encode(p.salt, msg.sender, p.name, p.symbol));
      token = new SomeToken{salt: salt}(p.name, p.symbol);
      require(expected == address(0) || address(token) == expected, "Invalid token address");

      tokenToNftId[token] = tokens.length;
      tokens.push(token);

      token.approve(address(adapter), type(uint256).max);
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

    _mint(msg.sender, tokenToNftId[token]);

    fundingToken.approve(address(adapter), type(uint256).max);

    // buy 1 token to register the token on tools like dexscreener
    uint256 swapped = adapter.swapWithExactInput(fundingToken, token, 1 ether, 0);

    // if the user wants to buy more tokens, they can do so
    uint256 received;
    if (amount > 0) {
      fundingToken.transferFrom(msg.sender, address(this), amount);
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
    require(msg.sender == cron || msg.sender == owner(), "!cron");
    _updateLaunchTicks(_launchTick, _graduationTick, _upperMaxTick);
  }

  function setCron(address _cron) external onlyOwner {
    cron = _cron;
    emit CronUpdated(_cron);
  }

  /// @inheritdoc ITokenLaunchpad
  function claimFees(IERC20 _token) external {
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
    launchTick = _launchTick;
    graduationTick = _graduationTick;
    upperMaxTick = _upperMaxTick;
    emit LaunchTicksUpdated(_launchTick, _graduationTick, _upperMaxTick);
  }
}
