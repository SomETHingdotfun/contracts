// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {UIHelper} from "contracts/launchpad/clmm/UIHelper.sol";

import {Test} from "lib/forge-std/src/Test.sol";
import {TestableTokenLaunchpad} from "test/TokenLaunchpadTest.sol";
import {MockCLMMAdapter} from "test/TokenLaunchpadTest.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

import "forge-std/console.sol";

/// @title MockWETH9
/// @notice Mock implementation of WETH9 for testing
contract MockWETH9 {
  string public name = "Wrapped Ether";
  string public symbol = "WETH";
  uint8 public decimals = 18;
  uint256 public totalSupply;

  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Deposit(address indexed dst, uint256 wad);
  event Withdrawal(address indexed src, uint256 wad);

  function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
    totalSupply += msg.value;
    emit Deposit(msg.sender, msg.value);
  }

  function withdraw(uint256 wad) public {
    require(balanceOf[msg.sender] >= wad, "Insufficient balance");
    balanceOf[msg.sender] -= wad;
    totalSupply -= wad;
    payable(msg.sender).transfer(wad);
    emit Withdrawal(msg.sender, wad);
  }

  function transfer(address to, uint256 amount) public returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    emit Transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) public returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    allowance[from][msg.sender] -= amount;

    emit Transfer(from, to, amount);
    return true;
  }

  function approve(address spender, uint256 amount) public returns (bool) {
    allowance[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }
}

/// @title MockODOS
/// @notice Mock implementation of ODOS router for testing
contract MockODOS {
  mapping(address => uint256) public mockOutputAmounts;
  bool public shouldRevert = false;
  bool public shouldRevertOnCall = false;

  function setMockOutput(address token, uint256 amount) external {
    mockOutputAmounts[token] = amount;
  }

  function setShouldRevert(bool _shouldRevert) external {
    shouldRevert = _shouldRevert;
  }

  function setShouldRevertOnCall(bool _shouldRevert) external {
    shouldRevertOnCall = _shouldRevert;
  }

  receive() external payable {
    if (shouldRevert) {
      revert("Mock ODOS revert");
    }
  }

  fallback() external payable {
    if (shouldRevertOnCall) {
      revert("Mock ODOS call revert");
    }
  }
}

contract UIHelperTest is Test {
  UIHelper uiHelper;
  TestableTokenLaunchpad launchpad;
  MockCLMMAdapter adapter;
  MockERC20 fundingToken;
  MockWETH9 weth;
  MockODOS odos;

  address owner;
  address user1;

  function setUp() public {
    owner = makeAddr("owner");
    user1 = makeAddr("user1");

    // Deploy mock contracts
    fundingToken = new MockERC20("Funding Token", "FUND", 18);
    adapter = new MockCLMMAdapter();
    launchpad = new TestableTokenLaunchpad();
    weth = new MockWETH9();
    odos = new MockODOS();

    // Initialize the launchpad
    launchpad.initialize(owner, address(fundingToken), address(adapter));

    // Deploy UIHelper
    uiHelper = new UIHelper(address(weth), address(odos), address(launchpad));

    // Fund users
    fundingToken.mint(user1, 1000 * 1e18);
    fundingToken.mint(address(this), 1000 * 1e18);

    // Fund the launchpad with funding tokens for the registration swap
    fundingToken.mint(address(launchpad), 10_000 * 1e18);

    // Fund the UIHelper with funding tokens for swaps
    fundingToken.mint(address(uiHelper), 10_000 * 1e18);

    // Fund WETH contract with some ETH for testing
    vm.deal(address(weth), 1000 ether);
  }

  // ============ Helper Functions ============

  function _createTokenInLaunchpad(string memory salt, string memory name, string memory symbol)
    internal
    returns (address token, uint256 tokenId)
  {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256(abi.encodePacked(salt)),
      name: name,
      symbol: symbol,
      metadata: string(abi.encodePacked("ipfs://", salt))
    });

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    vm.prank(user1);
    (token,,, tokenId) = uiHelper.createAndBuy(odosParams, params, address(0), 0);
  }

  // ============ Constructor Tests ============

  function test_constructor() public {
    assertEq(address(uiHelper.weth()), address(weth));
    assertEq(uiHelper.ODOS(), address(odos));
    assertEq(address(uiHelper.launchpad()), address(launchpad));
    assertEq(address(uiHelper.adapter()), address(adapter));
    assertEq(address(uiHelper.fundingToken()), address(fundingToken));

    // Check that funding token is approved for adapter and launchpad
    assertEq(fundingToken.allowance(address(uiHelper), address(adapter)), type(uint256).max);
    assertEq(fundingToken.allowance(address(uiHelper), address(launchpad)), type(uint256).max);
  }

  // ============ createAndBuy Tests ============

  function test_createAndBuy_withETH() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt"),
      name: "Test Token",
      symbol: "TEST",
      metadata: "ipfs://test"
    });

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)), // ETH
      tokenAmountIn: 0,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    vm.prank(user1);
    (address token, uint256 received, uint256 swapped, uint256 tokenId) =
      uiHelper.createAndBuy(odosParams, params, address(0), 0);

    // Verify token was created
    assertTrue(token != address(0));
    assertEq(launchpad.ownerOf(tokenId), user1);
    assertEq(received, 0);
    assertEq(swapped, adapter.mockSwapAmountOut());
  }

  function test_createAndBuy_withToken() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-2"),
      name: "Test Token 2",
      symbol: "TEST2",
      metadata: "ipfs://test2"
    });

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: fundingToken,
      tokenAmountIn: 100 * 1e18,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    vm.startPrank(user1);
    fundingToken.approve(address(uiHelper), 100 * 1e18);
    (address token, uint256 received, uint256 swapped, uint256 tokenId) =
      uiHelper.createAndBuy(odosParams, params, address(0), 0);
    vm.stopPrank();

    assertTrue(token != address(0));
    assertEq(launchpad.ownerOf(tokenId), user1);
    assertEq(received, 0);
    assertEq(swapped, adapter.mockSwapAmountOut());
  }

  function test_createAndBuy_withOdosSwap() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-3"),
      name: "Test Token 3",
      symbol: "TEST3",
      metadata: "ipfs://test3"
    });

    // Set up mock ODOS output
    odos.setMockOutput(address(fundingToken), 100 * 1e18);

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: IERC20(address(0)),
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: "mock-odos-data"
    });

    vm.prank(user1);
    (address token,,, uint256 tokenId) = uiHelper.createAndBuy(odosParams, params, address(0), 0);

    assertTrue(token != address(0));
    assertEq(launchpad.ownerOf(tokenId), user1);
  }

  // ============ buyWithExactInputWithOdos Tests ============

  function test_buyWithExactInputWithOdos_withToken() public {
    (address token,) = _createTokenInLaunchpad("test-buy-token", "Buy Token Token", "BUYTOKEN");

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: fundingToken,
      tokenAmountIn: 100 * 1e18,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    vm.startPrank(user1);
    fundingToken.approve(address(uiHelper), 100 * 1e18);
    uint256 amountOut = uiHelper.buyWithExactInputWithOdos(odosParams, IERC20(token), 0);
    vm.stopPrank();

    assertEq(amountOut, adapter.mockSwapAmountOut());
  }

  function test_buyWithExactInputWithOdos_withOdosData() public {
    (address token,) = _createTokenInLaunchpad("test-buy-odos", "Buy ODOS Token", "BUYODOS");

    // Set up mock ODOS output
    odos.setMockOutput(address(fundingToken), 100 * 1e18);

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: IERC20(address(0)),
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: "mock-odos-data"
    });

    vm.prank(user1);
    uint256 amountOut = uiHelper.buyWithExactInputWithOdos{value: 0}(odosParams, IERC20(token), 0);
  }

  function test_buyWithExactInputWithOdos_withInvalidMinAmountOut() public {
    (address token,) = _createTokenInLaunchpad("test-buy-invalid", "Buy Invalid Token", "BUYINV");

    // Set up mock ODOS output with insufficient amount
    odos.setMockOutput(address(fundingToken), 30 * 1e18);

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: IERC20(address(0)),
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 50 * 1e18,
      odosTokenOut: fundingToken,
      odosData: "mock-odos-data"
    });

    vm.prank(user1);
    vm.expectRevert("!minAmountIn");
    uiHelper.buyWithExactInputWithOdos{value: 0}(odosParams, IERC20(token), 0);
  }

  // ============ sellWithExactInputWithOdos Tests ============

  function test_sellWithExactInputWithOdos_basic() public {
    (address token,) = _createTokenInLaunchpad("test-sell-basic", "Sell Basic Token", "SELLBASIC");

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    uint256 amountToSell = 100 * 1e18;

    vm.startPrank(user1);
    IERC20(token).approve(address(uiHelper), amountToSell);
    uint256 amountSwapOut = uiHelper.sellWithExactInputWithOdos{value: 0}(odosParams, IERC20(token), amountToSell);
    vm.stopPrank();

    assertEq(amountSwapOut, adapter.mockSwapAmountOut());
  }

  function test_sellWithExactInputWithOdos_withOdosData() public {
    (address token,) = _createTokenInLaunchpad("test-sell-odos", "Sell ODOS Token", "SELLODOS");

    // Set up mock ODOS output
    odos.setMockOutput(address(fundingToken), 100 * 1e18);

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: IERC20(address(0)),
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: "mock-odos-data"
    });

    uint256 amountToSell = 100 * 1e18;

    vm.startPrank(user1);
    IERC20(token).approve(address(uiHelper), amountToSell);
    uint256 amountSwapOut = uiHelper.sellWithExactInputWithOdos{value: 0}(odosParams, IERC20(token), amountToSell);
    vm.stopPrank();

    assertEq(amountSwapOut, adapter.mockSwapAmountOut());
  }

  // ============ Purge Tests ============

  function test_purge_eth() public {
    // Send ETH to UIHelper
    vm.deal(address(uiHelper), 1 ether);

    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-purge"),
      name: "Purge Token",
      symbol: "PURGE",
      metadata: "ipfs://purge"
    });

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    uint256 initialBalance = user1.balance;

    vm.prank(user1);
    uiHelper.createAndBuy(odosParams, params, address(0), 0);

    // Check that ETH was purged (sent back to user)
    assertEq(user1.balance, initialBalance + 1 ether);
    assertEq(address(uiHelper).balance, 0);
  }

  function test_purge_token() public {
    // Create a test token and send some to UIHelper
    MockERC20 testToken = new MockERC20("Test Token", "TEST", 18);
    testToken.mint(address(uiHelper), 100 * 1e18);

    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-purge-token"),
      name: "Purge Token Test",
      symbol: "PURGE2",
      metadata: "ipfs://purge2"
    });

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    uint256 initialBalance = testToken.balanceOf(user1);

    vm.prank(user1);
    uiHelper.createAndBuy(odosParams, params, address(0), 0);
  }

  function test_purge_fundingToken() public {
    // Send funding token to UIHelper
    fundingToken.mint(address(uiHelper), 200 * 1e18);

    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-purge-funding"),
      name: "Purge Funding Token",
      symbol: "PURGE3",
      metadata: "ipfs://purge3"
    });

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    uint256 initialBalance = fundingToken.balanceOf(user1);

    vm.prank(user1);
    uiHelper.createAndBuy(odosParams, params, address(0), 0);
  }

  // ============ Error Cases Tests ============

  function test_odos_call_failure() public {
    // Set ODOS to revert on calls
    odos.setShouldRevertOnCall(true);

    (address token,) = _createTokenInLaunchpad("test-odos-fail", "ODOS Fail Token", "ODOSFAIL");

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: IERC20(address(0)),
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: "mock-odos-data"
    });

    vm.prank(user1);
    vm.expectRevert("Odos call failed");
    uiHelper.buyWithExactInputWithOdos{value: 0}(odosParams, IERC20(token), 0);
  }

  // ============ Receive Ether Test ============

  function test_receive_ether() public {
    // Test that UIHelper can receive ETH
    (bool success,) = address(uiHelper).call{value: 1 ether}("");
    assertTrue(success);
    assertEq(address(uiHelper).balance, 1 ether);
  }

  // ============ Fuzz Tests ============

  function test_fuzz_buyWithExactInputWithOdos(uint256 tokenAmount) public {
    // Bound the amount to reasonable values
    tokenAmount = bound(tokenAmount, 1 * 1e18, 1000 * 1e18);

    // First create a token in the launchpad so claimFees works
    (address token,) = _createTokenInLaunchpad("fuzz-buy", "Fuzz Buy Token", "FUZZBUY");

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: fundingToken,
      tokenAmountIn: tokenAmount,
      odosTokenIn: fundingToken,
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: fundingToken,
      odosData: ""
    });

    vm.startPrank(user1);
    fundingToken.approve(address(uiHelper), tokenAmount);
    uint256 amountOut = uiHelper.buyWithExactInputWithOdos(odosParams, IERC20(token), 0);
    vm.stopPrank();

    // Verify amount out
    assertEq(amountOut, adapter.mockSwapAmountOut());
  }

  // ============ Multiple Operations Tests ============

  function test_multiple_createAndBuy() public {
    // Create multiple tokens to test state management
    for (uint256 i = 0; i < 3; i++) {
      ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
        salt: keccak256(abi.encode("multi-salt", i)),
        name: string(abi.encodePacked("Multi Token ", i)),
        symbol: string(abi.encodePacked("MULTI", i)),
        metadata: string(abi.encodePacked("ipfs://multi", i))
      });

      UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
        tokenIn: IERC20(address(0)),
        tokenAmountIn: 0,
        odosTokenIn: fundingToken,
        odosTokenAmountIn: 0,
        minOdosTokenAmountOut: 0,
        odosTokenOut: fundingToken,
        odosData: ""
      });

      vm.prank(user1);
      (address token,,, uint256 tokenId) = uiHelper.createAndBuy(odosParams, params, address(0), 0);

      assertTrue(token != address(0));
      assertEq(launchpad.ownerOf(tokenId), user1);
    }

    assertEq(launchpad.getTotalTokens(), 3);
  }

  function test_multiple_buyWithExactInputWithOdos() public {
    // Create a token first
    (address token,) = _createTokenInLaunchpad("multi-buy", "Multi Buy Token", "MULTIBUY");

    // Perform multiple buy operations
    for (uint256 i = 0; i < 3; i++) {
      UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
        tokenIn: fundingToken,
        tokenAmountIn: 100 * 1e18,
        odosTokenIn: fundingToken,
        odosTokenAmountIn: 0,
        minOdosTokenAmountOut: 0,
        odosTokenOut: fundingToken,
        odosData: ""
      });

      vm.startPrank(user1);
      fundingToken.approve(address(uiHelper), 100 * 1e18);
      uint256 amountOut = uiHelper.buyWithExactInputWithOdos(odosParams, IERC20(token), 0);
      vm.stopPrank();

      assertEq(amountOut, adapter.mockSwapAmountOut());
    }
  }

  // ============ Edge Cases Tests ============

  function test_createAndBuy_withZeroAddress() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-zero"),
      name: "Zero Token",
      symbol: "ZERO",
      metadata: "ipfs://zero"
    });

    UIHelper.OdosParams memory odosParams = UIHelper.OdosParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      odosTokenIn: IERC20(address(0)),
      odosTokenAmountIn: 0,
      minOdosTokenAmountOut: 0,
      odosTokenOut: IERC20(address(0)),
      odosData: ""
    });

    vm.prank(user1);
    (address token,,, uint256 tokenId) = uiHelper.createAndBuy(odosParams, params, address(0), 0);

    assertTrue(token != address(0));
    assertEq(launchpad.ownerOf(tokenId), user1);
  }
}
