// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {SomeToken} from "contracts/SomeToken.sol";
import {IERC20, ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {TokenLaunchpadLinea} from "contracts/launchpad/TokenLaunchpadLinea.sol";

import {UIHelper} from "contracts/launchpad/clmm/UIHelper.sol";
import {RamsesAdapter} from "contracts/launchpad/clmm/adapters/RamsesAdapter.sol";

import {MockERC20} from "contracts/mocks/MockERC20.sol";
import {Test} from "lib/forge-std/src/Test.sol";

import "forge-std/console.sol";

contract TokenLaunchpadLineaTest is Test {
  IERC20 weth;
  MockERC20 something;

  TokenLaunchpadLinea launchpad;
  UIHelper swapper;

  RamsesAdapter adapter;

  address owner = makeAddr("owner");
  address whale = makeAddr("whale");
  address creator = makeAddr("creator");
  address feeDestination = makeAddr("feeDestination");

  function setUp() public {
    uint256 fork = vm.createFork("https://rpc.linea.build");
    vm.selectFork(fork);
    vm.rollFork(22_754_009);

    weth = IERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);

    launchpad = new TokenLaunchpadLinea();
    adapter = new RamsesAdapter();

    swapper = new UIHelper(address(weth), address(0), address(launchpad));
    something = new MockERC20("Something", "somETHing", 18);

    launchpad.initialize(owner, address(something), address(adapter));
    adapter.initialize(
      address(launchpad),
      address(0x8BE024b5c546B5d45CbB23163e1a4dca8fA5052A),
      address(0xA04A9F0a961f8fcc4a94bCF53e676B236cBb2F58),
      address(0xAe334f70A7FC44FCC2df9e6A37BC032497Cf80f1)
    );

    vm.prank(owner);
    launchpad.setLaunchTicks(-206_200, -180_000, 886_000);

    vm.label(address(weth), "weth");
    vm.label(address(something), "something");
    vm.label(address(swapper), "swapper");
    vm.label(address(adapter), "adapter");
    vm.label(address(launchpad), "launchpad");
    vm.label(address(0x8BE024b5c546B5d45CbB23163e1a4dca8fA5052A), "etherexSwapRouter");
    vm.label(address(0xA04A9F0a961f8fcc4a94bCF53e676B236cBb2F58), "etherexNFTPositionManager");
    vm.label(address(0xAe334f70A7FC44FCC2df9e6A37BC032497Cf80f1), "etherexFactory");

    vm.deal(owner, 1000 ether);
    vm.deal(whale, 1000 ether);
    vm.deal(creator, 1000 ether);

    vm.deal(address(this), 100 ether);
  }

  function test_createAndBuy_withNoAmount() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);

    deal(address(something), creator, 1e18);
    vm.startPrank(creator);

    something.approve(address(launchpad), 1e18);

    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      address(0),
      0
    );

    // assertEq(IERC20(token).balanceOf(creator), 0);
    assertApproxEqRel(IERC20(token).balanceOf(creator), 425_619_113 * 1e18, 1e18);
  }

  function test_createAndBuy_withAmount() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);

    deal(address(something), creator, 101e18);
    vm.startPrank(creator);

    something.approve(address(launchpad), 101e18);

    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      address(0),
      100e18
    );

    assertApproxEqRel(IERC20(token).balanceOf(creator), 976_001_149 * 1e18, 1e18);
  }

  function _findValidTokenHash(string memory _name, string memory _symbol, address _creator, IERC20 _quoteToken)
    internal
    view
    returns (bytes32)
  {
    // Get the runtime bytecode of WAGMIEToken
    bytes memory bytecode = type(SomeToken).creationCode;

    // Maximum number of attempts to find a valid address
    uint256 maxAttempts = 100;

    for (uint256 i = 0; i < maxAttempts; i++) {
      bytes32 salt = keccak256(abi.encode(i));
      bytes32 saltUser = keccak256(abi.encode(salt, _creator, _name, _symbol));

      // Calculate CREATE2 address
      bytes memory creationCode = abi.encodePacked(bytecode, abi.encode(_name, _symbol));
      bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(launchpad), saltUser, keccak256(creationCode)));
      address target = address(uint160(uint256(hash)));

      if (target < address(_quoteToken)) return salt;
    }

    revert(
      "No valid token address found after 100 attempts. Try increasing maxAttempts or using a different quote token."
    );
  }

  receive() external payable {
    // do nothing; we're not using this
  }
}
