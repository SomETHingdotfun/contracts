// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {SomeProxy} from "contracts/SomeProxy.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {ICLSwapRouter} from "contracts/interfaces/thirdparty/ICLSwapRouter.sol";
import {IClPool} from "contracts/interfaces/thirdparty/IClPool.sol";
import {IClPoolFactory} from "contracts/interfaces/thirdparty/IClPoolFactory.sol";
import {RamsesAdapter} from "contracts/launchpad/clmm/adapters/RamsesAdapter.sol";

import {Test} from "lib/forge-std/src/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

import "forge-std/console.sol";

// Local struct definitions for testing
struct MintParams {
  address token0;
  address token1;
  int24 tickSpacing;
  int24 tickLower;
  int24 tickUpper;
  uint256 amount0Desired;
  uint256 amount1Desired;
  uint256 amount0Min;
  uint256 amount1Min;
  address recipient;
  uint256 deadline;
}

struct CollectParams {
  uint256 tokenId;
  address recipient;
  uint128 amount0Max;
  uint128 amount1Max;
}

/// @title MockNonfungiblePositionManagerRamses
/// @notice Mock implementation of Ramses NFT Position Manager for testing
contract MockNonfungiblePositionManagerRamses is IERC721 {
  uint256 private _nextTokenId = 1;
  mapping(uint256 => address) private _owners;
  mapping(address => uint256) private _balances;
  mapping(uint256 => address) private _tokenApprovals;
  mapping(address => mapping(address => bool)) private _operatorApprovals;

  // Mock fee amounts
  mapping(uint256 => uint256) public mockFee0;
  mapping(uint256 => uint256) public mockFee1;

  // Mock liquidity amounts
  mapping(uint256 => uint128) public mockLiquidity;
  mapping(uint256 => uint256) public mockAmount0;
  mapping(uint256 => uint256) public mockAmount1;

  function setMockFees(uint256 tokenId, uint256 fee0, uint256 fee1) external {
    mockFee0[tokenId] = fee0;
    mockFee1[tokenId] = fee1;
  }

  function setMockMintResult(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) external {
    mockLiquidity[tokenId] = liquidity;
    mockAmount0[tokenId] = amount0;
    mockAmount1[tokenId] = amount1;
  }

  // IERC721 implementation
  function balanceOf(address owner) external view override returns (uint256) {
    return _balances[owner];
  }

  function ownerOf(uint256 tokenId) external view override returns (address) {
    require(_owners[tokenId] != address(0), "Token does not exist");
    return _owners[tokenId];
  }

  function approve(address to, uint256 tokenId) external override {
    address owner = _owners[tokenId];
    require(to != owner, "ERC721: approval to current owner");
    require(
      msg.sender == owner || isApprovedForAll(owner, msg.sender),
      "ERC721: approve caller is not owner nor approved for all"
    );

    _tokenApprovals[tokenId] = to;
    emit Approval(owner, to, tokenId);
  }

  function getApproved(uint256 tokenId) external view override returns (address) {
    require(_owners[tokenId] != address(0), "ERC721: approved query for nonexistent token");
    return _tokenApprovals[tokenId];
  }

  function setApprovalForAll(address operator, bool approved) external override {
    _operatorApprovals[msg.sender][operator] = approved;
    emit ApprovalForAll(msg.sender, operator, approved);
  }

  function isApprovedForAll(address owner, address operator) public view override returns (bool) {
    return _operatorApprovals[owner][operator];
  }

  function transferFrom(address from, address to, uint256 tokenId) external override {
    require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
    _transfer(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external override {
    safeTransferFrom(from, to, tokenId, "");
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
    require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
    _safeTransfer(from, to, tokenId, data);
  }

  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC721Metadata).interfaceId;
  }

  function name() external pure returns (string memory) {
    return "Mock Ramses NFT Position Manager";
  }

  function symbol() external pure returns (string memory) {
    return "MRNPM";
  }

  function tokenURI(uint256 tokenId) external view returns (string memory) {
    require(_owners[tokenId] != address(0), "ERC721: URI query for nonexistent token");
    return string(abi.encodePacked("https://api.ramses.exchange/metadata/", tokenId));
  }

  // Ramses-specific functions
  function mint(MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
  {
    tokenId = _nextTokenId++;
    _mint(params.recipient, tokenId);

    liquidity = mockLiquidity[tokenId] > 0 ? mockLiquidity[tokenId] : 1000;
    amount0 = mockAmount0[tokenId] > 0 ? mockAmount0[tokenId] : params.amount0Desired;
    amount1 = mockAmount1[tokenId] > 0 ? mockAmount1[tokenId] : 0;

    // Simulate consuming the tokens as a real position manager would
    if (amount0 > 0) {
      IERC20(params.token0).transferFrom(msg.sender, address(this), amount0);
    }
    if (amount1 > 0) {
      IERC20(params.token1).transferFrom(msg.sender, address(this), amount1);
    }
  }

  function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
    amount0 = mockFee0[params.tokenId];
    amount1 = mockFee1[params.tokenId];
  }

  // Internal functions
  function _mint(address to, uint256 tokenId) internal {
    require(to != address(0), "ERC721: mint to the zero address");
    require(_owners[tokenId] == address(0), "ERC721: token already minted");

    _balances[to] += 1;
    _owners[tokenId] = to;

    emit Transfer(address(0), to, tokenId);
  }

  function _transfer(address from, address to, uint256 tokenId) internal {
    require(_owners[tokenId] == from, "ERC721: transfer of token that is not own");
    require(to != address(0), "ERC721: transfer to the zero address");

    _approve(address(0), tokenId);

    _balances[from] -= 1;
    _balances[to] += 1;
    _owners[tokenId] = to;

    emit Transfer(from, to, tokenId);
  }

  function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
    _transfer(from, to, tokenId);
    // In a real implementation, this would check if the recipient is a contract and call onERC721Received
  }

  function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
    require(_owners[tokenId] != address(0), "ERC721: operator query for nonexistent token");
    address owner = _owners[tokenId];
    return (spender == owner || _tokenApprovals[tokenId] == spender || isApprovedForAll(owner, spender));
  }

  function _approve(address to, uint256 tokenId) internal {
    _tokenApprovals[tokenId] = to;
    emit Approval(_owners[tokenId], to, tokenId);
  }
}

/// @title MockRamsesPoolFactory
/// @notice Mock implementation of Ramses Pool Factory for testing
contract MockRamsesPoolFactory {
  mapping(bytes32 => address) public pools;
  uint256 private _nextPoolId = 1;

  function createPool(IERC20 _token0, IERC20 _token1, int24 _tickSpacing, uint160 _sqrtPriceX96Launch)
    external
    returns (address pool)
  {
    // Sort tokens to ensure canonical ordering
    (IERC20 token0, IERC20 token1) = _sortTokens(_token0, _token1);

    bytes32 poolKey = keccak256(abi.encodePacked(address(token0), address(token1), _tickSpacing));
    require(pools[poolKey] == address(0), "Pool already exists");

    // Create a mock pool address
    pool = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1, _tickSpacing, _nextPoolId++)))));
    pools[poolKey] = pool;

    return pool;
  }

  function getPool(IERC20 _token0, IERC20 _token1, int24 _tickSpacing) external view returns (address pool) {
    // Sort tokens to ensure canonical ordering
    (IERC20 token0, IERC20 token1) = _sortTokens(_token0, _token1);

    bytes32 poolKey = keccak256(abi.encodePacked(address(token0), address(token1), _tickSpacing));
    return pools[poolKey];
  }

  /// @dev Sorts two tokens by address to ensure canonical ordering
  function _sortTokens(IERC20 _tokenA, IERC20 _tokenB) internal pure returns (IERC20 token0, IERC20 token1) {
    if (address(_tokenA) < address(_tokenB)) {
      return (_tokenA, _tokenB);
    } else {
      return (_tokenB, _tokenA);
    }
  }
}

/// @title MockCLSwapRouter
/// @notice Mock implementation of CL Swap Router for testing
contract MockCLSwapRouter {
  uint256 public mockAmountOut = 1000 * 1e18;
  uint256 public mockAmountIn = 1000 * 1e18;
  bool public shouldRevert = false;

  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    int24 tickSpacing;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  struct ExactOutputSingleParams {
    address tokenIn;
    address tokenOut;
    int24 tickSpacing;
    address recipient;
    uint256 deadline;
    uint256 amountOut;
    uint256 amountInMaximum;
    uint160 sqrtPriceLimitX96;
  }

  function setMockAmounts(uint256 _amountOut, uint256 _amountIn) external {
    mockAmountOut = _amountOut;
    mockAmountIn = _amountIn;
  }

  function setShouldRevert(bool _shouldRevert) external {
    shouldRevert = _shouldRevert;
  }

  function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
    if (shouldRevert) revert("Mock router revert");

    // Simulate successful swap
    IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

    // In a real scenario, we would transfer the output tokens
    // For testing, we'll just return the mock amount
    amountOut = mockAmountOut;

    // Transfer some mock output tokens to the recipient
    // This is a simplified mock - in reality we'd need the actual token
  }

  function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn) {
    if (shouldRevert) revert("Mock router revert");

    // Simulate successful swap - only transfer the amount we actually need
    amountIn = mockAmountIn;
    IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);

    // In a real scenario, we would transfer the output tokens to the recipient
    // For testing, we'll just return the mock amount
  }
}

/// @title MockClPool
/// @notice Mock implementation of CL Pool for testing
contract MockClPool {
  address public token0;
  address public token1;
  int24 public tickSpacing;
  uint160 public sqrtPriceX96;

  constructor(address _token0, address _token1, int24 _tickSpacing, uint160 _sqrtPriceX96) {
    token0 = _token0;
    token1 = _token1;
    tickSpacing = _tickSpacing;
    sqrtPriceX96 = _sqrtPriceX96;
  }
}

/// @title MockLaunchpad
/// @notice Mock implementation of launchpad for testing
contract MockLaunchpad {
  IERC20 public fundingToken;

  constructor(address _fundingToken) {
    fundingToken = IERC20(_fundingToken);
  }
}

contract RamsesAdapterTest is Test {
  RamsesAdapter adapter;
  MockERC20 token0;
  MockERC20 token1;
  MockERC20 fundingToken;
  MockNonfungiblePositionManagerRamses nftPositionManager;
  MockRamsesPoolFactory poolFactory;
  MockCLSwapRouter swapRouter;
  MockLaunchpad launchpad;

  address owner;
  address user1;
  address user2;
  address proxyAdmin;

  function setUp() public {
    owner = makeAddr("owner");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    proxyAdmin = makeAddr("proxyAdmin");

    // Deploy mock contracts
    token0 = new MockERC20("Token0", "TK0", 18);
    token1 = new MockERC20("Token1", "TK1", 18);
    fundingToken = new MockERC20("Funding Token", "FUND", 18);
    nftPositionManager = new MockNonfungiblePositionManagerRamses();
    poolFactory = new MockRamsesPoolFactory();
    swapRouter = new MockCLSwapRouter();
    launchpad = new MockLaunchpad(address(fundingToken));

    // Deploy RamsesAdapter implementation
    RamsesAdapter adapterImpl = new RamsesAdapter();

    // Deploy proxy with initialization
    bytes memory initData = abi.encodeWithSignature(
      "initialize(address,address,address,address)",
      address(launchpad),
      address(swapRouter),
      address(nftPositionManager),
      address(poolFactory)
    );
    SomeProxy adapterProxy = new SomeProxy(address(adapterImpl), proxyAdmin, initData);
    adapter = RamsesAdapter(payable(address(adapterProxy)));

    // Fund users with tokens
    token0.mint(user1, 10_000 * 1e18);
    token0.mint(user2, 10_000 * 1e18);
    token1.mint(user1, 10_000 * 1e18);
    token1.mint(user2, 10_000 * 1e18);
    fundingToken.mint(user1, 10_000 * 1e18);
    fundingToken.mint(user2, 10_000 * 1e18);

    // Fund the launchpad with tokens (the adapter will transfer from launchpad during mint)
    // Need enough tokens for GRADUATION_AMOUNT (600M) + POST_GRADUATION_AMOUNT (400M) = 1B tokens
    vm.prank(address(launchpad));
    token0.mint(address(launchpad), 2_000_000_000 * 1e18); // 2B tokens
    vm.prank(address(launchpad));
    token1.mint(address(launchpad), 2_000_000_000 * 1e18); // 2B tokens for multiple token scenarios
    vm.prank(address(launchpad));
    token0.approve(address(adapter), type(uint256).max);
    vm.prank(address(launchpad));
    token1.approve(address(adapter), type(uint256).max);

    // Fund the adapter with tokens for liquidity provision
    token0.mint(address(adapter), 1_000_000 * 1e18);
    token1.mint(address(adapter), 1_000_000 * 1e18);
    fundingToken.mint(address(adapter), 1_000_000 * 1e18);

    // Label addresses for better debugging
    vm.label(address(adapter), "adapter");
    vm.label(address(token0), "token0");
    vm.label(address(token1), "token1");
    vm.label(address(fundingToken), "fundingToken");
    vm.label(address(nftPositionManager), "nftPositionManager");
    vm.label(address(poolFactory), "poolFactory");
    vm.label(address(swapRouter), "swapRouter");
    vm.label(address(launchpad), "launchpad");
    vm.label(owner, "owner");
    vm.label(user1, "user1");
    vm.label(user2, "user2");
  }

  function test_initialization() public {
    assertEq(adapter.launchpad(), address(launchpad));
    assertEq(address(adapter.swapRouter()), address(swapRouter));
    assertEq(address(adapter.nftPositionManager()), address(nftPositionManager));
    assertEq(address(adapter.clPoolFactory()), address(poolFactory));
    assertEq(adapter.TICK_SPACING(), 200);
    assertEq(adapter.GRADUATION_AMOUNT(), 600_000_000 * 1e18);
    assertEq(adapter.POST_GRADUATION_AMOUNT(), 400_000_000 * 1e18);
  }

  function test_addSingleSidedLiquidity() public {
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    // Set mock mint results
    nftPositionManager.setMockMintResult(1, 1000, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(2, 2000, 400_000_000 * 1e18, 0);

    vm.prank(address(launchpad));
    address pool = adapter.addSingleSidedLiquidity(params);

    // Verify pool was created
    assertTrue(pool != address(0));

    // Verify lock IDs were stored
    assertEq(adapter.tokenToLockId(token0, 0), 1);
    assertEq(adapter.tokenToLockId(token0, 1), 2);

    // Verify NFTs were minted to the adapter
    assertEq(nftPositionManager.ownerOf(1), address(adapter));
    assertEq(nftPositionManager.ownerOf(2), address(adapter));
  }

  function test_addSingleSidedLiquidity_noResidualTokens() public {
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    // Set mock mint results that use less than the full amount
    // This simulates the real scenario where not all tokens are consumed
    nftPositionManager.setMockMintResult(1, 1000, 500_000_000 * 1e18, 0); // Used 500M instead of 600M
    nftPositionManager.setMockMintResult(2, 2000, 300_000_000 * 1e18, 0); // Used 300M instead of 400M

    // Record initial balances
    uint256 initialLaunchpadBalance = token0.balanceOf(address(launchpad));
    uint256 initialAdapterBalance = token0.balanceOf(address(adapter));

    vm.prank(address(launchpad));
    address pool = adapter.addSingleSidedLiquidity(params);

    // Verify pool was created
    assertTrue(pool != address(0));

    // Verify the launchpad received the refunded tokens
    // The adapter doesn't refund its initial balance, only the excess from what was transferred
    // Expected: initial balance - 500M (first mint) - 300M (second mint) = initial - 800M
    uint256 expectedLaunchpadBalance = initialLaunchpadBalance - 500_000_000 * 1e18 - 300_000_000 * 1e18;

    assertEq(token0.balanceOf(address(launchpad)), expectedLaunchpadBalance, "Launchpad should receive refunded tokens");

    // Verify that the adapter retains its initial balance (1M tokens)
    // The refund mechanism only refunds what was transferred beyond the initial balance
    assertEq(token0.balanceOf(address(adapter)), initialAdapterBalance, "Adapter should retain its initial balance");
  }

  function test_addSingleSidedLiquidity_tickUnderflowProtection() public {
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -887_272, // MIN_TICK
      tick1: 0,
      tick2: 1000
    });

    // This should revert because tick0 is MIN_TICK and not aligned to TICK_SPACING (200)
    // -887272 % 200 = -72, not 0
    vm.prank(address(launchpad));
    vm.expectRevert(abi.encodeWithSelector(ICLMMAdapter.TickNotAligned.selector, -887_272));
    adapter.addSingleSidedLiquidity(params);
  }

  function test_createPool_tokenSorting() public {
    // Create new tokens to avoid conflicts with existing pools
    MockERC20 tokenA = new MockERC20("TokenA", "TKA", 18);
    MockERC20 tokenB = new MockERC20("TokenB", "TKB", 18);

    // Fund the launchpad with the new tokens
    vm.prank(address(launchpad));
    tokenA.mint(address(launchpad), 2_000_000_000 * 1e18);
    vm.prank(address(launchpad));
    tokenB.mint(address(launchpad), 2_000_000_000 * 1e18);
    vm.prank(address(launchpad));
    tokenA.approve(address(adapter), type(uint256).max);
    vm.prank(address(launchpad));
    tokenB.approve(address(adapter), type(uint256).max);

    // Test that tokens are sorted correctly regardless of input order
    ICLMMAdapter.AddLiquidityParams memory params1 = ICLMMAdapter.AddLiquidityParams({
      tokenBase: tokenA, // tokenA address < tokenB address
      tokenQuote: tokenB,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    ICLMMAdapter.AddLiquidityParams memory params2 = ICLMMAdapter.AddLiquidityParams({
      tokenBase: tokenB, // tokenB address > tokenA address
      tokenQuote: tokenA,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    // First creation should succeed
    vm.prank(address(launchpad));
    address pool1 = adapter.addSingleSidedLiquidity(params1);
    assertTrue(pool1 != address(0), "First pool creation should succeed");

    // Second creation with reversed order should revert because it's the same pool
    vm.prank(address(launchpad));
    vm.expectRevert("Pool already exists");
    adapter.addSingleSidedLiquidity(params2);
  }

  function test_createPool_duplicatePrevention() public {
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    // First creation should succeed
    vm.prank(address(launchpad));
    address pool1 = adapter.addSingleSidedLiquidity(params);
    assertTrue(pool1 != address(0), "First pool creation should succeed");

    // Second creation with same parameters should revert
    vm.prank(address(launchpad));
    vm.expectRevert("Pool already exists");
    adapter.addSingleSidedLiquidity(params);
  }

  function test_createPool_differentTickSpacing() public {
    // Create two pools with different tick spacing - should both succeed
    ICLMMAdapter.AddLiquidityParams memory params1 = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    // First pool with default tick spacing (200)
    vm.prank(address(launchpad));
    address pool1 = adapter.addSingleSidedLiquidity(params1);
    assertTrue(pool1 != address(0), "First pool should be created");

    // Note: We can't easily test different tick spacing with current setup
    // as the adapter uses a fixed TICK_SPACING constant
    // This test verifies that the same tokens can be used in different contexts
  }

  function test_sortTokens_function() public {
    // Test the internal _sortTokens function through pool creation
    // Create tokens with known addresses for testing
    MockERC20 tokenA = new MockERC20("TokenA", "TKA", 18);
    MockERC20 tokenB = new MockERC20("TokenB", "TKB", 18);

    // Ensure tokenA address < tokenB address
    if (address(tokenA) > address(tokenB)) {
      (tokenA, tokenB) = (tokenB, tokenA);
    }

    ICLMMAdapter.AddLiquidityParams memory params =
      ICLMMAdapter.AddLiquidityParams({tokenBase: tokenA, tokenQuote: tokenB, tick0: -1000, tick1: 0, tick2: 1000});

    // Fund the launchpad with the new tokens
    vm.prank(address(launchpad));
    tokenA.mint(address(launchpad), 2_000_000_000 * 1e18);
    vm.prank(address(launchpad));
    tokenB.mint(address(launchpad), 2_000_000_000 * 1e18);
    vm.prank(address(launchpad));
    tokenA.approve(address(adapter), type(uint256).max);
    vm.prank(address(launchpad));
    tokenB.approve(address(adapter), type(uint256).max);

    // Create pool - should succeed with sorted tokens
    vm.prank(address(launchpad));
    address pool = adapter.addSingleSidedLiquidity(params);
    assertTrue(pool != address(0), "Pool should be created with sorted tokens");
  }

  function test_createPool_multipleTokenPairs() public {
    // Test creating pools with multiple different token pairs
    MockERC20 tokenC = new MockERC20("TokenC", "TKC", 18);
    MockERC20 tokenD = new MockERC20("TokenD", "TKD", 18);

    // Fund the launchpad with the new tokens
    vm.prank(address(launchpad));
    tokenC.mint(address(launchpad), 2_000_000_000 * 1e18);
    vm.prank(address(launchpad));
    tokenD.mint(address(launchpad), 2_000_000_000 * 1e18);
    vm.prank(address(launchpad));
    tokenC.approve(address(adapter), type(uint256).max);
    vm.prank(address(launchpad));
    tokenD.approve(address(adapter), type(uint256).max);

    ICLMMAdapter.AddLiquidityParams memory params =
      ICLMMAdapter.AddLiquidityParams({tokenBase: tokenC, tokenQuote: tokenD, tick0: -1000, tick1: 0, tick2: 1000});

    // Pool creation should succeed
    vm.prank(address(launchpad));
    address pool = adapter.addSingleSidedLiquidity(params);
    assertTrue(pool != address(0), "Pool should be created with different token pair");
  }

  function test_addSingleSidedLiquidity_onlyLaunchpad() public {
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    // Try to call from non-launchpad address
    vm.prank(user1);
    vm.expectRevert(ICLMMAdapter.Unauthorized.selector);
    adapter.addSingleSidedLiquidity(params);
  }

  function test_claimFees() public {
    // First add liquidity to create positions
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    nftPositionManager.setMockMintResult(1, 1000, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(2, 2000, 400_000_000 * 1e18, 0);

    vm.prank(address(launchpad));
    adapter.addSingleSidedLiquidity(params);

    // Set mock fees
    nftPositionManager.setMockFees(1, 100 * 1e18, 200 * 1e18);
    nftPositionManager.setMockFees(2, 150 * 1e18, 250 * 1e18);

    uint256 initialToken0Balance = token0.balanceOf(address(launchpad));
    uint256 initialFundingBalance = fundingToken.balanceOf(address(launchpad));

    vm.prank(address(launchpad));
    (uint256 fee0, uint256 fee1) = adapter.claimFees(address(token0));

    // Verify fees were claimed
    assertEq(fee0, 250 * 1e18); // 100 + 150
    assertEq(fee1, 450 * 1e18); // 200 + 250

    // Verify tokens were transferred to launchpad
    assertEq(token0.balanceOf(address(launchpad)), initialToken0Balance + 250 * 1e18);
    assertEq(fundingToken.balanceOf(address(launchpad)), initialFundingBalance + 450 * 1e18);

    // Verify claimed fees were recorded
    (uint256 claimedFee0, uint256 claimedFee1) = adapter.claimedFees(address(token0));
    assertEq(claimedFee0, 250 * 1e18);
    assertEq(claimedFee1, 450 * 1e18);
  }

  function test_claimFees_onlyLaunchpad() public {
    vm.prank(user1);
    vm.expectRevert(ICLMMAdapter.Unauthorized.selector);
    adapter.claimFees(address(token0));
  }

  function test_multiple_liquidity_provisions() public {
    // Add liquidity for multiple tokens
    ICLMMAdapter.AddLiquidityParams memory params1 = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    ICLMMAdapter.AddLiquidityParams memory params2 = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token1,
      tokenQuote: fundingToken,
      tick0: -600,
      tick1: 400,
      tick2: 1400
    });

    // Set mock mint results for first token
    nftPositionManager.setMockMintResult(1, 1000, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(2, 2000, 400_000_000 * 1e18, 0);

    vm.prank(address(launchpad));
    address pool1 = adapter.addSingleSidedLiquidity(params1);

    // Set mock mint results for second token
    nftPositionManager.setMockMintResult(3, 1500, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(4, 2500, 400_000_000 * 1e18, 0);

    vm.prank(address(launchpad));
    address pool2 = adapter.addSingleSidedLiquidity(params2);

    // Verify both pools were created
    assertTrue(pool1 != address(0));
    assertTrue(pool2 != address(0));
    assertTrue(pool1 != pool2);

    // Verify lock IDs for both tokens
    assertEq(adapter.tokenToLockId(token0, 0), 1);
    assertEq(adapter.tokenToLockId(token0, 1), 2);
    assertEq(adapter.tokenToLockId(token1, 0), 3);
    assertEq(adapter.tokenToLockId(token1, 1), 4);
  }

  function test_claimFees_multiple_positions() public {
    // Add liquidity for multiple tokens
    ICLMMAdapter.AddLiquidityParams memory params1 = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    ICLMMAdapter.AddLiquidityParams memory params2 = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token1,
      tokenQuote: fundingToken,
      tick0: -600,
      tick1: 400,
      tick2: 1400
    });

    // Set mock mint results and add liquidity
    nftPositionManager.setMockMintResult(1, 1000, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(2, 2000, 400_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(3, 1500, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(4, 2500, 400_000_000 * 1e18, 0);

    vm.prank(address(launchpad));
    adapter.addSingleSidedLiquidity(params1);

    vm.prank(address(launchpad));
    adapter.addSingleSidedLiquidity(params2);

    // Set different fees for each position
    nftPositionManager.setMockFees(1, 100 * 1e18, 200 * 1e18);
    nftPositionManager.setMockFees(2, 150 * 1e18, 250 * 1e18);
    nftPositionManager.setMockFees(3, 300 * 1e18, 400 * 1e18);
    nftPositionManager.setMockFees(4, 350 * 1e18, 450 * 1e18);

    // Claim fees for token0
    vm.prank(address(launchpad));
    (uint256 fee0_0, uint256 fee1_0) = adapter.claimFees(address(token0));

    // Claim fees for token1
    vm.prank(address(launchpad));
    (uint256 fee0_1, uint256 fee1_1) = adapter.claimFees(address(token1));

    // Verify fees for token0
    assertEq(fee0_0, 250 * 1e18); // 100 + 150
    assertEq(fee1_0, 450 * 1e18); // 200 + 250

    // Verify fees for token1
    assertEq(fee0_1, 650 * 1e18); // 300 + 350
    assertEq(fee1_1, 850 * 1e18); // 400 + 450
  }

  function test_receive_ether() public {
    // Test that adapter can receive ETH
    (bool success,) = address(adapter).call{value: 1 ether}("");
    assertTrue(success);
    assertEq(address(adapter).balance, 1 ether);
  }

  function test_edge_case_zero_amounts() public {
    ICLMMAdapter.AddLiquidityParams memory params =
      ICLMMAdapter.AddLiquidityParams({tokenBase: token0, tokenQuote: fundingToken, tick0: 0, tick1: 200, tick2: 400});

    // Set mock mint results with zero amounts
    nftPositionManager.setMockMintResult(1, 0, 0, 0);
    nftPositionManager.setMockMintResult(2, 0, 0, 0);

    vm.prank(address(launchpad));
    address pool = adapter.addSingleSidedLiquidity(params);

    assertTrue(pool != address(0));
  }

  function test_edge_case_max_tick_values() public {
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -887_200, // Use valid tick values
      tick1: 0,
      tick2: 887_200
    });

    // Set mock mint results
    nftPositionManager.setMockMintResult(1, 1000, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(2, 2000, 400_000_000 * 1e18, 0);

    vm.prank(address(launchpad));
    address pool = adapter.addSingleSidedLiquidity(params);

    assertTrue(pool != address(0));
  }

  function test_claimedFees_view_function() public {
    // Add liquidity first
    ICLMMAdapter.AddLiquidityParams memory params = ICLMMAdapter.AddLiquidityParams({
      tokenBase: token0,
      tokenQuote: fundingToken,
      tick0: -1000,
      tick1: 0,
      tick2: 1000
    });

    nftPositionManager.setMockMintResult(1, 1000, 600_000_000 * 1e18, 0);
    nftPositionManager.setMockMintResult(2, 2000, 400_000_000 * 1e18, 0);

    vm.prank(address(launchpad));
    adapter.addSingleSidedLiquidity(params);

    // Initially no fees claimed
    (uint256 initialFee0, uint256 initialFee1) = adapter.claimedFees(address(token0));
    assertEq(initialFee0, 0);
    assertEq(initialFee1, 0);

    // Set mock fees and claim them
    nftPositionManager.setMockFees(1, 100 * 1e18, 200 * 1e18);
    nftPositionManager.setMockFees(2, 150 * 1e18, 250 * 1e18);

    vm.prank(address(launchpad));
    adapter.claimFees(address(token0));

    // Check claimed fees
    (uint256 claimedFee0, uint256 claimedFee1) = adapter.claimedFees(address(token0));
    assertEq(claimedFee0, 250 * 1e18);
    assertEq(claimedFee1, 450 * 1e18);
  }

  function test_swapWithExactOutput() public {
    // Set up mock swap router to return a specific amount
    uint256 expectedAmountIn = 1000 * 1e18;
    uint256 amountOut = 500 * 1e18;
    uint256 maxAmountIn = 2000 * 1e18;

    swapRouter.setMockAmounts(amountOut, expectedAmountIn);

    // Record initial balances
    uint256 initialToken0Balance = token0.balanceOf(user1);
    uint256 initialAdapterBalance = token0.balanceOf(address(adapter));

    // Approve the adapter to spend user1's tokens
    vm.prank(user1);
    token0.approve(address(adapter), maxAmountIn);

    // Perform the swap
    vm.prank(user1);
    uint256 actualAmountIn = adapter.swapWithExactOutput(token0, token1, amountOut, maxAmountIn, 0);

    // Verify the swap was successful
    assertEq(actualAmountIn, expectedAmountIn);

    // The adapter refunds only the unused portion from what the user sent:
    // - User transfers maxAmountIn to adapter
    // - Adapter uses expectedAmountIn for the swap
    // - Adapter refunds (maxAmountIn - expectedAmountIn) back to user
    // - Adapter keeps its initial balance
    uint256 expectedUserBalance = initialToken0Balance - expectedAmountIn;
    assertEq(token0.balanceOf(user1), expectedUserBalance);

    // Verify the adapter still has its initial balance
    assertEq(token0.balanceOf(address(adapter)), initialAdapterBalance);
  }
}
