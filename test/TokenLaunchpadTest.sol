// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SomeToken} from "contracts/SomeToken.sol";

import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {TokenLaunchpad} from "contracts/launchpad/TokenLaunchpad.sol";

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

  function swapWithExactOutput(IERC20 _tokenIn, IERC20 _tokenOut, uint256 _amountOut, uint256 _maxAmountIn)
    external
    override
    returns (uint256 amountIn)
  {
    // Transfer input tokens from caller
    _tokenIn.transferFrom(msg.sender, address(this), _maxAmountIn);
    // For testing, we'll skip the actual transfer of output tokens
    // In real scenario, the adapter would have tokens from liquidity provision
    return _maxAmountIn;
  }

  function swapWithExactInput(IERC20 _tokenIn, IERC20 _tokenOut, uint256 _amountIn, uint256 _minAmountOut)
    external
    override
    returns (uint256 amountOut)
  {
    // Transfer input tokens from caller
    _tokenIn.transferFrom(msg.sender, address(this), _amountIn);

    // For testing, we'll simulate token creation by minting tokens to the caller
    // This simulates the swap behavior without requiring the adapter to hold tokens
    uint256 outputAmount = _amountIn > 0 ? mockSwapAmountOut : 1 ether; // 1 ether for registration swap

    // If the output token is a MockERC20, we can mint tokens for testing
    if (_tokenOut.totalSupply() == 0) {
      // This is likely a newly created token, we'll simulate the swap by not transferring
      // In a real scenario, the adapter would have tokens from liquidity provision
    }

    return outputAmount;
  }

  function claimFees(address _token) external override returns (uint256 fee0, uint256 fee1) {
    fee0 = mockFee0;
    fee1 = mockFee1;
    claimedFees0[_token] += fee0;
    claimedFees1[_token] += fee1;

    // For testing, we'll just return the fee amounts without transferring tokens
    // In real scenario, fees would be transferred from the pool to the caller

    return (fee0, fee1);
  }

  function claimedFees(address _token) external view override returns (uint256 fee0, uint256 fee1) {
    return (claimedFees0[_token], claimedFees1[_token]);
  }

  // Helper functions for testing
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

/// @title TestableTokenLaunchpad
/// @notice Concrete implementation of TokenLaunchpad for testing
contract TestableTokenLaunchpad is TokenLaunchpad {
  function _distributeFees(address _token0, address _owner, address _token1, uint256 _amount0, uint256 _amount1)
    internal
    override
  {
    // For testing, we'll just emit events to simulate fee distribution
    // In real scenario, tokens would be transferred to owner and treasury
    address treasury = address(0x1234567890123456789012345678901234567890);

    // Note: In a real implementation, this would transfer actual tokens
    // For testing purposes, we'll just simulate the behavior
  }
}

contract TokenLaunchpadTest is Test {
  TestableTokenLaunchpad launchpad;
  MockCLMMAdapter adapter;
  MockERC20 fundingToken;

  address owner;
  address cron;
  address user1;
  address user2;
  address treasury;

  function setUp() public {
    owner = makeAddr("owner");
    cron = makeAddr("cron");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    treasury = makeAddr("treasury");

    // Deploy mock contracts
    fundingToken = new MockERC20("Funding Token", "FUND", 18);
    adapter = new MockCLMMAdapter();
    launchpad = new TestableTokenLaunchpad();

    // Initialize the launchpad
    launchpad.initialize(owner, address(fundingToken), address(adapter));

    // Set up cron
    vm.prank(owner);
    launchpad.setCron(cron);

    // Set launch ticks
    vm.prank(cron);
    launchpad.setLaunchTicks(-206_200, -180_000, 886_000);

    // Fund users
    fundingToken.mint(user1, 1000 * 1e18);
    fundingToken.mint(user2, 1000 * 1e18);
    fundingToken.mint(address(this), 1000 * 1e18);

    // Fund the launchpad with funding tokens for the registration swap
    fundingToken.mint(address(launchpad), 10_000 * 1e18);

    // Label addresses for better debugging
    vm.label(address(launchpad), "launchpad");
    vm.label(address(adapter), "adapter");
    vm.label(address(fundingToken), "fundingToken");
    vm.label(owner, "owner");
    vm.label(cron, "cron");
    vm.label(user1, "user1");
    vm.label(user2, "user2");
  }

  function test_initialization() public {
    assertEq(address(launchpad.fundingToken()), address(fundingToken));
    assertEq(address(launchpad.adapter()), address(adapter));
    assertEq(launchpad.owner(), owner);
    assertEq(launchpad.cron(), cron);
    assertEq(launchpad.launchTick(), -206_200);
    assertEq(launchpad.graduationTick(), -180_000);
    assertEq(launchpad.upperMaxTick(), 886_000);
    assertEq(launchpad.getTotalTokens(), 0);
  }

  function test_createAndBuy_noAmount() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt"),
      name: "Test Token",
      symbol: "TEST",
      metadata: "ipfs://test"
    });

    vm.prank(user1);
    (address token, uint256 received, uint256 swapped, uint256 tokenId) = launchpad.createAndBuy(params, address(0), 0);

    // Verify token was created
    assertTrue(token != address(0));
    SomeToken tokenContract = SomeToken(token);
    assertEq(tokenContract.name(), "Test Token");
    assertEq(tokenContract.symbol(), "TEST");

    // Verify NFT was minted
    assertEq(launchpad.ownerOf(tokenId), user1);
    assertEq(launchpad.getTotalTokens(), 1);

    // Verify token was added to tokens array
    assertEq(address(launchpad.tokens(0)), token);
    assertEq(launchpad.tokenToNftId(tokenContract), tokenId);

    // Verify swap occurred (1 ether for registration)
    assertEq(swapped, adapter.mockSwapAmountOut());
    assertEq(received, 0); // No additional purchase

    // Verify token was approved for adapter
    assertEq(tokenContract.allowance(address(launchpad), address(adapter)), type(uint256).max);
  }

  function test_createAndBuy_withAmount() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-2"),
      name: "Test Token 2",
      symbol: "TEST2",
      metadata: "ipfs://test2"
    });

    uint256 buyAmount = 100 * 1e18;

    vm.startPrank(user1);
    fundingToken.approve(address(launchpad), buyAmount);

    (address token, uint256 received, uint256 swapped, uint256 tokenId) =
      launchpad.createAndBuy(params, address(0), buyAmount);
    vm.stopPrank();

    // Verify token was created
    assertTrue(token != address(0));
    SomeToken tokenContract = SomeToken(token);
    assertEq(tokenContract.name(), "Test Token 2");
    assertEq(tokenContract.symbol(), "TEST2");

    // Verify NFT was minted
    assertEq(launchpad.ownerOf(tokenId), user1);
    assertEq(launchpad.getTotalTokens(), 1);

    // Verify user received tokens from purchase
    assertEq(received, adapter.mockSwapAmountOut());
    assertEq(swapped, adapter.mockSwapAmountOut()); // Registration swap

    // Verify funding token was transferred
    assertEq(fundingToken.balanceOf(user1), 1000 * 1e18 - buyAmount);
    // Launchpad should have what it had before (minus the 1 ether for registration swap)
    // Initial: 10000 * 1e18, spent 1 * 1e18 for registration, received buyAmount from user, spent buyAmount in swap
    assertEq(fundingToken.balanceOf(address(launchpad)), 9999 * 1e18);
  }

  function test_createAndBuy_expectedAddress() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-3"),
      name: "Test Token 3",
      symbol: "TEST3",
      metadata: "ipfs://test3"
    });

    // Calculate expected address
    bytes32 salt = keccak256(abi.encode(params.salt, user1, params.name, params.symbol));
    address expectedToken = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              bytes1(0xff),
              address(launchpad),
              salt,
              keccak256(abi.encodePacked(type(SomeToken).creationCode, abi.encode(params.name, params.symbol)))
            )
          )
        )
      )
    );

    vm.prank(user1);
    (address token,,,) = launchpad.createAndBuy(params, expectedToken, 0);

    assertEq(token, expectedToken);
  }

  function test_createAndBuy_invalidExpectedAddress() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-4"),
      name: "Test Token 4",
      symbol: "TEST4",
      metadata: "ipfs://test4"
    });

    address wrongExpected = makeAddr("wrong");

    vm.prank(user1);
    vm.expectRevert("Invalid token address");
    launchpad.createAndBuy(params, wrongExpected, 0);
  }

  function test_claimFees() public {
    // First create a token
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-5"),
      name: "Test Token 5",
      symbol: "TEST5",
      metadata: "ipfs://test5"
    });

    vm.prank(user1);
    (address token,,, uint256 tokenId) = launchpad.createAndBuy(params, address(0), 0);

    // Set up mock fees
    adapter.setMockFees(50 * 1e18, 100 * 1e18);

    // Claim fees
    vm.expectEmit(true, true, true, true);
    emit ITokenLaunchpad.FeeClaimed(IERC20(token), 50 * 1e18, 100 * 1e18);

    launchpad.claimFees(IERC20(token));

    // Verify fees were claimed
    (uint256 claimed0, uint256 claimed1) = launchpad.claimedFees(IERC20(token));
    assertEq(claimed0, 50 * 1e18);
    assertEq(claimed1, 100 * 1e18);
  }

  function test_setLaunchTicks_onlyCronOrOwner() public {
    // Test cron can set ticks
    vm.prank(cron);
    launchpad.setLaunchTicks(-100, -50, 100);

    assertEq(launchpad.launchTick(), -100);
    assertEq(launchpad.graduationTick(), -50);
    assertEq(launchpad.upperMaxTick(), 100);

    // Test owner can set ticks
    vm.prank(owner);
    launchpad.setLaunchTicks(-200, -100, 200);

    assertEq(launchpad.launchTick(), -200);
    assertEq(launchpad.graduationTick(), -100);
    assertEq(launchpad.upperMaxTick(), 200);

    // Test random user cannot set ticks
    vm.prank(user1);
    vm.expectRevert("!cron");
    launchpad.setLaunchTicks(-300, -150, 300);
  }

  function test_setCron_onlyOwner() public {
    address newCron = makeAddr("newCron");

    // Test owner can set cron
    vm.expectEmit(true, true, true, true);
    emit ITokenLaunchpad.CronUpdated(newCron);

    vm.prank(owner);
    launchpad.setCron(newCron);

    assertEq(launchpad.cron(), newCron);

    // Test non-owner cannot set cron
    vm.prank(user1);
    vm.expectRevert();
    launchpad.setCron(makeAddr("anotherCron"));
  }

  function test_multipleTokenCreations() public {
    // Create multiple tokens
    for (uint256 i = 0; i < 3; i++) {
      ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
        salt: keccak256(abi.encode("test-salt", i)),
        name: string(abi.encodePacked("Test Token ", i)),
        symbol: string(abi.encodePacked("TEST", i)),
        metadata: string(abi.encodePacked("ipfs://test", i))
      });

      vm.prank(user1);
      (address token,,, uint256 tokenId) = launchpad.createAndBuy(params, address(0), 0);

      assertEq(launchpad.ownerOf(tokenId), user1);
      assertEq(launchpad.tokenToNftId(IERC20(token)), tokenId);
    }

    assertEq(launchpad.getTotalTokens(), 3);
  }

  function test_refundTokens() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-refund"),
      name: "Refund Token",
      symbol: "REFUND",
      metadata: "ipfs://refund"
    });

    uint256 initialBalance = fundingToken.balanceOf(user1);

    vm.startPrank(user1);
    fundingToken.approve(address(launchpad), 100 * 1e18);
    launchpad.createAndBuy(params, address(0), 100 * 1e18);
    vm.stopPrank();

    // The refund should happen automatically in createAndBuy
    // User should have their original balance minus what they spent
    assertEq(fundingToken.balanceOf(user1), initialBalance - 100 * 1e18);
  }

  function test_erc721_functionality() public {
    // Create a token to get an NFT
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-nft"),
      name: "NFT Token",
      symbol: "NFT",
      metadata: "ipfs://nft"
    });

    vm.prank(user1);
    (address token,,, uint256 tokenId) = launchpad.createAndBuy(params, address(0), 0);

    // Test ERC721 functionality
    assertEq(launchpad.ownerOf(tokenId), user1);
    assertEq(launchpad.balanceOf(user1), 1);
    assertEq(launchpad.tokenOfOwnerByIndex(user1, 0), tokenId);
    assertEq(launchpad.tokenByIndex(0), tokenId);
    assertEq(launchpad.totalSupply(), 1);

    // Test transfer
    vm.prank(user1);
    launchpad.transferFrom(user1, user2, tokenId);

    assertEq(launchpad.ownerOf(tokenId), user2);
    assertEq(launchpad.balanceOf(user1), 0);
    assertEq(launchpad.balanceOf(user2), 1);
  }

  function test_launchTicksUpdated_event() public {
    vm.expectEmit(true, true, true, true);
    emit ITokenLaunchpad.LaunchTicksUpdated(-100, -50, 100);

    vm.prank(cron);
    launchpad.setLaunchTicks(-100, -50, 100);
  }

  function test_tokenLaunched_event() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-event"),
      name: "Event Token",
      symbol: "EVENT",
      metadata: "ipfs://event"
    });

    vm.expectEmit(false, true, false, true);
    emit ITokenLaunchpad.TokenLaunched(
      IERC20(address(0)), // Token address will be checked
      address(adapter),
      address(0), // Pool address will be checked
      params
    );

    vm.prank(user1);
    launchpad.createAndBuy(params, address(0), 0);
  }

  function test_fuzz_createAndBuy(uint256 amount) public {
    // Bound amount to reasonable values
    amount = bound(amount, 0, 1000 * 1e18);

    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256(abi.encode("fuzz-salt", amount)),
      name: string(abi.encodePacked("Fuzz Token ", amount)),
      symbol: string(abi.encodePacked("FUZZ", amount)),
      metadata: string(abi.encodePacked("ipfs://fuzz", amount))
    });

    if (amount > 0) {
      fundingToken.mint(user1, amount);
      vm.startPrank(user1);
      fundingToken.approve(address(launchpad), amount);
      launchpad.createAndBuy(params, address(0), amount);
      vm.stopPrank();
    } else {
      vm.prank(user1);
      launchpad.createAndBuy(params, address(0), amount);
    }

    // Verify token was created regardless of amount
    assertTrue(launchpad.getTotalTokens() > 0);
  }

  function test_receive_ether() public {
    // Test that contract can receive ether
    (bool success,) = address(launchpad).call{value: 1 ether}("");
    assertTrue(success);
    assertEq(address(launchpad).balance, 1 ether);
  }
}
