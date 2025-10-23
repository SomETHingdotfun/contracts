// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SomeToken} from "contracts/SomeToken.sol";

import {SomeProxy} from "contracts/SomeProxy.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {IERC20, ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {TokenLaunchpadLinea} from "contracts/launchpad/TokenLaunchpadLinea.sol";

import {Test} from "lib/forge-std/src/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

import "forge-std/console.sol";

/// @title MockCLMMAdapter
/// @notice Mock implementation of ICLMMAdapter for testing
contract MockCLMMAdapter is ICLMMAdapter {
  address public launchpad;
  mapping(address => uint256) public claimedFees0;
  mapping(address => uint256) public claimedFees1;

  // Mock pool addresses for different tokens
  mapping(address => address) public tokenToPool;

  // Mock swap amounts
  uint256 public mockSwapAmountOut = 1000 * 1e18;
  uint256 public mockSwapAmountIn = 1000 * 1e18;

  // Mock fee amounts
  uint256 public mockFee0 = 100 * 1e18;
  uint256 public mockFee1 = 200 * 1e18;

  constructor() {
    launchpad = msg.sender;
  }

  function addSingleSidedLiquidity(AddLiquidityParams memory _params) external override returns (address pool) {
    // Mock pool address based on token addresses
    pool =
      address(uint160(uint256(keccak256(abi.encodePacked(_params.tokenBase, _params.tokenQuote, block.timestamp)))));
    tokenToPool[address(_params.tokenBase)] = pool;

    // For testing, we'll just approve the adapter to spend tokens but not transfer them
    // In a real scenario, tokens would be transferred to the pool for liquidity
    return pool;
  }

  function swapWithExactOutput(
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _amountOut,
    uint256 _maxAmountIn,
    uint160 _sqrtPriceLimitX96
  ) external override returns (uint256 amountIn) {
    // Mock implementation - return the mock amount
    return mockSwapAmountIn;
  }

  function swapWithExactInput(
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _amountIn,
    uint256 _minAmountOut,
    uint160 _sqrtPriceLimitX96
  ) external override returns (uint256 amountOut) {
    // Mock implementation - return the mock amount
    return mockSwapAmountOut;
  }

  function claimFees(address _token) external override returns (uint256 fee0, uint256 fee1) {
    // Return mock fees
    fee0 = mockFee0;
    fee1 = mockFee1;

    // Update claimed fees for testing
    claimedFees0[_token] += fee0;
    claimedFees1[_token] += fee1;
  }

  function claimedFees(address _token) external view override returns (uint256 fee0, uint256 fee1) {
    return (claimedFees0[_token], claimedFees1[_token]);
  }

  function setMockSwapAmountOut(uint256 _amount) external {
    mockSwapAmountOut = _amount;
  }

  function setMockSwapAmountIn(uint256 _amount) external {
    mockSwapAmountIn = _amount;
  }

  function setMockFees(uint256 _fee0, uint256 _fee1) external {
    mockFee0 = _fee0;
    mockFee1 = _fee1;
  }
}

contract TokenLaunchpadLineaTest is Test {
  MockERC20 something;
  TokenLaunchpadLinea launchpad;
  MockCLMMAdapter adapter;

  address owner = makeAddr("owner");
  address whale = makeAddr("whale");
  address creator = makeAddr("creator");
  address proxyAdmin = makeAddr("proxyAdmin");
  address etherxTreasury = 0x8EfeFDBe3f3f7D48b103CD220d634CBF1d0Ae1a6;
  address somethingTreasury = 0x8EfeFDBe3f3f7D48b103CD220d634CBF1d0Ae1a6; // Same as etherxTreasury in the contract

  function setUp() public {
    // Deploy mock contracts
    something = new MockERC20("SomeETHing", "somETHing", 18);
    adapter = new MockCLMMAdapter();

    // Deploy implementation contract
    TokenLaunchpadLinea launchpadImpl = new TokenLaunchpadLinea();

    // Deploy proxy with initialization
    bytes memory initData =
      abi.encodeWithSignature("initialize(address,address,address)", owner, address(something), address(adapter));
    SomeProxy launchpadProxy = new SomeProxy(address(launchpadImpl), proxyAdmin, initData);
    launchpad = TokenLaunchpadLinea(payable(address(launchpadProxy)));

    // Set launch ticks
    vm.prank(owner);
    launchpad.setLaunchTicks(-206_200, -180_000, 886_000);

    // Set up mock adapter
    adapter.setMockSwapAmountOut(1000e18);
    adapter.setMockFees(100e18, 200e18);

    // Label addresses for debugging
    vm.label(address(something), "something");
    vm.label(address(adapter), "adapter");
    vm.label(address(launchpad), "launchpad");
    vm.label(etherxTreasury, "etherxTreasury");
    vm.label(somethingTreasury, "somethingTreasury");

    // Fund accounts
    vm.deal(owner, 1000 ether);
    vm.deal(whale, 1000 ether);
    vm.deal(creator, 1000 ether);
    vm.deal(address(this), 100 ether);
    deal(address(something), address(launchpad), 1000e18);
  }

  // Test initialization
  function test_initialization() public {
    assertEq(address(launchpad.fundingToken()), address(something));
    assertEq(address(launchpad.adapter()), address(adapter));
    assertEq(launchpad.owner(), owner);
    assertEq(launchpad.cron(), owner);
    assertEq(launchpad.launchTick(), -206_200);
    assertEq(launchpad.graduationTick(), -180_000);
    assertEq(launchpad.upperMaxTick(), 886_000);
  }

  // Test createAndBuy with no amount
  function test_createAndBuy_withNoAmount() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);

    deal(address(something), creator, 1e18);
    vm.startPrank(creator);

    address computedAddress = _calculateExpectedAddress(salt, creator, "Test Token", "TEST");
    assertEq(computedAddress != address(0), true);

    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      computedAddress,
      0
    );

    // Verify token was created and creator received tokens
    assertTrue(token != address(0));
    assertGt(IERC20(token).balanceOf(creator), 0);

    // Verify NFT was minted to creator
    assertEq(launchpad.balanceOf(creator), 1);
    assertEq(launchpad.ownerOf(0), creator);

    // Verify token was added to tokens array
    assertEq(launchpad.getTotalTokens(), 1);
    assertEq(address(launchpad.tokens(0)), token);

    vm.stopPrank();
  }

  // Test createAndBuy with amount
  function test_createAndBuy_withAmount() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);

    deal(address(something), creator, 101e18);
    vm.startPrank(creator);

    something.approve(address(launchpad), 101e18);

    address computedAddress = _calculateExpectedAddress(salt, creator, "Test Token", "TEST");
    (address token, uint256 received,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      computedAddress,
      100e18
    );

    // Verify token was created and creator received tokens
    assertTrue(token != address(0));
    assertGt(received, 0);
    assertGt(IERC20(token).balanceOf(creator), 0);

    // Verify NFT was minted to creator
    assertEq(launchpad.balanceOf(creator), 1);
    assertEq(launchpad.ownerOf(0), creator);

    vm.stopPrank();
  }

  // Test fee distribution
  function test_feeDistribution() public {
    // Create a token first
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);
    deal(address(something), creator, 1e18);

    vm.startPrank(creator);
    something.approve(address(launchpad), 1e18);
    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      address(0),
      0
    );
    vm.stopPrank();

    // Give tokens to the launchpad contract for fee distribution
    // The fee distribution will transfer from the launchpad to treasuries
    deal(address(token), address(launchpad), 1000e18);
    deal(address(something), address(launchpad), 2000e18);

    // The actual treasury addresses in TokenLaunchpadLinea
    address referralContract = 0x0000000000000000000000000000000000000001;
    address somethingTreasury = 0x0000000000000000000000000000000000000002;

    // Record initial balances
    uint256 referralToken0Before = SomeToken(token).balanceOf(referralContract);
    uint256 treasuryToken0Before = SomeToken(token).balanceOf(somethingTreasury);
    uint256 creatorToken0Before = SomeToken(token).balanceOf(creator);
    uint256 referralToken1Before = something.balanceOf(referralContract);
    uint256 treasuryToken1Before = something.balanceOf(somethingTreasury);
    uint256 creatorToken1Before = something.balanceOf(creator);

    // Set mock fees in the adapter
    adapter.setMockFees(1000e18, 2000e18);

    // Claim fees
    launchpad.claimFees(SomeToken(token));

    // Verify fee distribution for token0 (the created token)
    // 15% to referral, 50% to treasury, 35% to creator
    assertEq(SomeToken(token).balanceOf(referralContract), referralToken0Before + 150e18); // 15% of 1000
    assertEq(SomeToken(token).balanceOf(somethingTreasury), treasuryToken0Before + 500e18); // 50% of 1000
    assertEq(SomeToken(token).balanceOf(creator), creatorToken0Before + 350e18); // 35% of 1000

    // Verify fee distribution for token1 (funding token)
    // 15% to referral, 50% to treasury, 35% to creator
    assertEq(something.balanceOf(referralContract), referralToken1Before + 300e18); // 15% of 2000
    assertEq(something.balanceOf(somethingTreasury), treasuryToken1Before + 1000e18); // 50% of 2000
    assertEq(something.balanceOf(creator), creatorToken1Before + 700e18); // 35% of 2000
  }

  // Test fee distribution with zero amounts
  function test_feeDistribution_zeroAmounts() public {
    // Create a token first
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);
    deal(address(something), creator, 1e18);

    vm.startPrank(creator);
    something.approve(address(launchpad), 1e18);
    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      address(0),
      0
    );
    vm.stopPrank();

    // Create mock tokens
    MockERC20 token0 = new MockERC20("Token0", "T0", 18);
    MockERC20 token1 = new MockERC20("Token1", "T1", 18);

    // Record initial balances
    uint256 etherxTreasuryToken0Before = token0.balanceOf(etherxTreasury);
    uint256 somethingTreasuryToken0Before = token0.balanceOf(somethingTreasury);
    uint256 etherxTreasuryToken1Before = token1.balanceOf(etherxTreasury);
    uint256 somethingTreasuryToken1Before = token1.balanceOf(somethingTreasury);

    // Set mock fees to zero in the adapter
    adapter.setMockFees(0, 0);

    // Claim fees
    launchpad.claimFees(token0);

    // Verify no fees were distributed
    assertEq(token0.balanceOf(etherxTreasury), etherxTreasuryToken0Before);
    assertEq(token0.balanceOf(somethingTreasury), somethingTreasuryToken0Before);
    assertEq(token1.balanceOf(etherxTreasury), etherxTreasuryToken1Before);
    assertEq(token1.balanceOf(somethingTreasury), somethingTreasuryToken1Before);
  }

  // Test multiple token creations
  function test_multipleTokenCreations() public {
    deal(address(something), creator, 10e18);
    vm.startPrank(creator);
    something.approve(address(launchpad), 10e18);

    // Create first token
    bytes32 salt1 = _findValidTokenHash("Token1", "T1", creator, something);
    (address token1,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt1, name: "Token1", symbol: "T1", metadata: "Metadata1"}), address(0), 0
    );

    // Create second token
    bytes32 salt2 = _findValidTokenHash("Token2", "T2", creator, something);
    (address token2,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt2, name: "Token2", symbol: "T2", metadata: "Metadata2"}), address(0), 0
    );

    // Verify both tokens were created
    assertTrue(token1 != address(0));
    assertTrue(token2 != address(0));
    assertTrue(token1 != token2);

    // Verify NFT count
    assertEq(launchpad.balanceOf(creator), 2);
    assertEq(launchpad.ownerOf(0), creator);
    assertEq(launchpad.ownerOf(1), creator);

    // Verify total tokens count
    assertEq(launchpad.getTotalTokens(), 2);
    assertEq(address(launchpad.tokens(0)), token1);
    assertEq(address(launchpad.tokens(1)), token2);

    vm.stopPrank();
  }

  // Test setLaunchTicks access control
  function test_setLaunchTicks_accessControl() public {
    // Test that only owner can set launch ticks (aligned to TICK_SPACING = 200)
    vm.prank(whale);
    vm.expectRevert();
    launchpad.setLaunchTicks(-200, 0, 200);

    // Test that cron can set launch ticks (aligned to TICK_SPACING = 200)
    vm.prank(owner);
    launchpad.setLaunchTicks(-200, 0, 200);
    assertEq(launchpad.launchTick(), -200);
    assertEq(launchpad.graduationTick(), 0);
    assertEq(launchpad.upperMaxTick(), 200);
  }

  // Test setCron access control
  function test_setCron_accessControl() public {
    address newCron = makeAddr("newCron");

    // Test that only owner can set cron
    vm.prank(whale);
    vm.expectRevert();
    launchpad.setCron(newCron);

    // Test that owner can set cron
    vm.prank(owner);
    launchpad.setCron(newCron);
    assertEq(launchpad.cron(), newCron);
  }

  // Test refund functionality
  function test_refundTokens() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);
    deal(address(something), creator, 1e18);

    vm.startPrank(creator);
    something.approve(address(launchpad), 1e18);
    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      address(0),
      0
    );
    vm.stopPrank();

    // The refund should happen automatically during createAndBuy
    // Since the mock adapter doesn't actually transfer tokens, the launchpad should have some tokens
    // Let's verify that the creator received some tokens from the refund
    assertGt(IERC20(token).balanceOf(creator), 0);

    // The launchpad should have minimal tokens left after refund
    // (it should only have tokens that were used for the initial swap)
    assertLt(IERC20(token).balanceOf(address(launchpad)), 1000e18);
  }

  // Test ERC721 functionality
  function test_erc721_functionality() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);
    deal(address(something), creator, 1e18);

    vm.startPrank(creator);
    something.approve(address(launchpad), 1e18);
    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      address(0),
      0
    );
    vm.stopPrank();

    // Test ERC721 functions
    assertEq(launchpad.name(), "Something.fun");
    assertEq(launchpad.symbol(), "somETHing");
    assertEq(launchpad.balanceOf(creator), 1);
    assertEq(launchpad.ownerOf(0), creator);
    assertEq(launchpad.tokenByIndex(0), 0);
    assertEq(launchpad.tokenOfOwnerByIndex(creator, 0), 0);

    // Test transfer
    vm.prank(creator);
    launchpad.transferFrom(creator, whale, 0);
    assertEq(launchpad.ownerOf(0), whale);
    assertEq(launchpad.balanceOf(creator), 0);
    assertEq(launchpad.balanceOf(whale), 1);
  }

  // Test edge case: createAndBuy with expected address validation
  function test_createAndBuy_expectedAddress() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);
    deal(address(something), creator, 1e18);

    vm.startPrank(creator);
    something.approve(address(launchpad), 1e18);

    // Calculate expected address
    address expected = _calculateExpectedAddress(salt, creator, "Test Token", "TEST");

    (address token,,,) = launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      expected,
      0
    );

    assertEq(token, expected);
    vm.stopPrank();
  }

  // Test edge case: createAndBuy with invalid expected address
  function test_createAndBuy_invalidExpectedAddress() public {
    bytes32 salt = _findValidTokenHash("Test Token", "TEST", creator, something);
    deal(address(something), creator, 1e18);

    vm.startPrank(creator);
    something.approve(address(launchpad), 1e18);

    // Use wrong expected address
    address wrongExpected = makeAddr("wrong");

    vm.expectRevert(ITokenLaunchpad.InvalidTokenAddress.selector);
    launchpad.createAndBuy(
      ITokenLaunchpad.CreateParams({salt: salt, name: "Test Token", symbol: "TEST", metadata: "Test Metadata"}),
      wrongExpected,
      0
    );

    vm.stopPrank();
  }

  // Helper function to find valid token hash
  function _findValidTokenHash(string memory _name, string memory _symbol, address _creator, IERC20 _quoteToken)
    internal
    view
    returns (bytes32)
  {
    // Get the runtime bytecode of SomeToken
    bytes memory bytecode = type(SomeToken).creationCode;

    // Maximum number of attempts to find a valid address
    uint256 maxAttempts = 100;

    for (uint256 i = 0; i < maxAttempts; i++) {
      // Use a more unique salt generation that includes iteration-specific data
      // This ensures each call gets a different salt even in the same block
      bytes32 salt = keccak256(abi.encode(i, block.timestamp, block.number));

      // Use the launchpad's computeTokenAddress method
      (address computedAddress, bool isValid) = launchpad.computeTokenAddress(
        ITokenLaunchpad.CreateParams({salt: salt, name: _name, symbol: _symbol, metadata: ""}),
        address(_quoteToken),
        _creator
      );

      if (isValid) return salt;
    }

    revert(
      "No valid token address found after 100 attempts. Try increasing maxAttempts or using a different quote token."
    );
  }

  // Helper function to calculate expected address
  function _calculateExpectedAddress(bytes32 _salt, address _creator, string memory _name, string memory _symbol)
    internal
    view
    returns (address)
  {
    bytes32 saltUser = keccak256(abi.encode(_salt, _creator, _name, _symbol));
    bytes memory bytecode = type(SomeToken).creationCode;
    bytes memory creationCode = abi.encodePacked(bytecode, abi.encode(_name, _symbol));
    bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(launchpad), saltUser, keccak256(creationCode)));
    return address(uint160(uint256(hash)));
  }

  receive() external payable {
    // do nothing; we're not using this
  }
}
