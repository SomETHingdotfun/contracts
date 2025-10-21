// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {UIHelper} from "contracts/launchpad/clmm/UIHelper.sol";
import {SomeProxy} from "contracts/SomeProxy.sol";

import {Test} from "lib/forge-std/src/Test.sol";
import {TestableTokenLaunchpad} from "test/TokenLaunchpadTest.sol";
import {MockCLMMAdapter} from "test/TokenLaunchpadTest.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {IUIHelper} from "contracts/interfaces/IUIHelper.sol";
import {IOpenOceanCaller, IOpenOceanExchange} from "contracts/interfaces/thirdparty/IOpenOcean.sol";

// import "forge-std/console.sol";

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

/// @title MockOpenOcean
/// @notice Mock implementation of OpenOcean router for testing
contract MockOpenOcean is IOpenOceanExchange {
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

  function swap(
    IOpenOceanCaller caller,
    SwapDescription memory desc,
    IOpenOceanCaller.CallDescription[] calldata calls
  ) external payable override returns (uint256) {
    if (shouldRevertOnCall) {
      revert("Mock OpenOcean call revert");
    }
    return mockOutputAmounts[address(desc.dstToken)];
  }

  receive() external payable {
    if (shouldRevert) {
      revert("Mock OpenOcean revert");
    }
  }

  fallback() external payable {
    if (shouldRevertOnCall) {
      revert("Mock OpenOcean call revert");
    }
  }
}

contract UIHelperTest is Test {
  UIHelper uiHelper;
  TestableTokenLaunchpad launchpad;
  MockCLMMAdapter adapter;
  MockERC20 fundingToken;
  MockWETH9 weth;
  MockOpenOcean openOcean;

  address owner;
  address user1;
  address proxyAdmin;

  function setUp() public {
    owner = makeAddr("owner");
    user1 = makeAddr("user1");
    proxyAdmin = makeAddr("proxyAdmin");

    // Deploy mock contracts
    fundingToken = new MockERC20("Funding Token", "FUND", 18);
    adapter = new MockCLMMAdapter();
    weth = new MockWETH9();
    openOcean = new MockOpenOcean();
    
    // Deploy implementation contract
    TestableTokenLaunchpad launchpadImpl = new TestableTokenLaunchpad();
    
    // Deploy proxy with initialization
    bytes memory initData = abi.encodeWithSignature(
      "initialize(address,address,address)",
      owner,
      address(fundingToken),
      address(adapter)
    );
    SomeProxy launchpadProxy = new SomeProxy(
      address(launchpadImpl),
      proxyAdmin,
      initData
    );
    launchpad = TestableTokenLaunchpad(payable(address(launchpadProxy)));

    // Deploy UIHelper
    uiHelper = new UIHelper(address(weth), address(openOcean), address(launchpad));

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

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    vm.prank(user1);
    (token,,, tokenId) = uiHelper.createAndBuy(openOceanParams, params, address(0), 0);
  }

  // ============ Constructor Tests ============

  function test_constructor() public {
    assertEq(address(uiHelper.weth()), address(weth));
    assertEq(address(uiHelper.openOcean()), address(openOcean));
    assertEq(address(uiHelper.launchpad()), address(launchpad));
    assertEq(address(uiHelper.adapter()), address(adapter));
    assertEq(address(uiHelper.fundingToken()), address(fundingToken));

    // Check that funding token is NOT approved for adapter and launchpad (safe-approve pattern)
    assertEq(fundingToken.allowance(address(uiHelper), address(adapter)), 0);
    assertEq(fundingToken.allowance(address(uiHelper), address(launchpad)), 0);
  }

  // ============ createAndBuy Tests ============

  function test_createAndBuy_withETH() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt"),
      name: "Test Token",
      symbol: "TEST",
      metadata: "ipfs://test"
    });

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)), // ETH
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    vm.prank(user1);
    (address token, uint256 received, uint256 swapped, uint256 tokenId) =
      uiHelper.createAndBuy(openOceanParams, params, address(0), 0);

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

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: fundingToken,
      tokenAmountIn: 100 * 1e18,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    vm.startPrank(user1);
    fundingToken.approve(address(uiHelper), 100 * 1e18);
    (address token, uint256 received, uint256 swapped, uint256 tokenId) =
      uiHelper.createAndBuy(openOceanParams, params, address(0), 0);
    vm.stopPrank();

    assertTrue(token != address(0));
    assertEq(launchpad.ownerOf(tokenId), user1);
    assertEq(received, 0);
    assertEq(swapped, adapter.mockSwapAmountOut());
  }

  function test_createAndBuy_withOpenOceanSwap() public {
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      salt: keccak256("test-salt-3"),
      name: "Test Token 3",
      symbol: "TEST3",
      metadata: "ipfs://test3"
    });

    // Set up mock OpenOcean output
    openOcean.setMockOutput(address(fundingToken), 100 * 1e18);

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](1)
    });

    vm.prank(user1);
    (address token,,, uint256 tokenId) = uiHelper.createAndBuy(openOceanParams, params, address(0), 0);

    assertTrue(token != address(0));
    assertEq(launchpad.ownerOf(tokenId), user1);
  }

  // ============ buyWithExactInputWithOpenOcean Tests ============

  function test_buyWithExactInputWithOpenOcean_withToken() public {
    (address token,) = _createTokenInLaunchpad("test-buy-token", "Buy Token Token", "BUYTOKEN");

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: fundingToken,
      tokenAmountIn: 100 * 1e18,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    vm.startPrank(user1);
    fundingToken.approve(address(uiHelper), 100 * 1e18);
    uint256 amountOut = uiHelper.buyWithExactInputWithOpenOcean(openOceanParams, IERC20(token), 0, 0);
    vm.stopPrank();

    assertEq(amountOut, adapter.mockSwapAmountOut());
  }

  function test_buyWithExactInputWithOpenOcean_withOpenOceanData() public {
    (address token,) = _createTokenInLaunchpad("test-buy-openocean", "Buy OpenOcean Token", "BUYOPENOCEAN");

    // Set up mock OpenOcean output
    openOcean.setMockOutput(address(fundingToken), 100 * 1e18);

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](1)
    });

    vm.prank(user1);
    uint256 amountOut = uiHelper.buyWithExactInputWithOpenOcean{value: 0}(openOceanParams, IERC20(token), 0, 0);
  }

  function test_buyWithExactInputWithOpenOcean_withInvalidMinAmountOut() public {
    (address token,) = _createTokenInLaunchpad("test-buy-invalid", "Buy Invalid Token", "BUYINV");

    // Set up mock OpenOcean output with insufficient amount
    openOcean.setMockOutput(address(fundingToken), 30 * 1e18);

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 50 * 1e18,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](1)
    });

    vm.prank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(IUIHelper.InsufficientOutputAmount.selector, 30 * 1e18, 50 * 1e18)
    );
    uiHelper.buyWithExactInputWithOpenOcean{value: 0}(openOceanParams, IERC20(token), 0, 0);
  }

  // ============ sellWithExactInputWithOpenOcean Tests ============

  function test_sellWithExactInputWithOpenOcean_basic() public {
    (address token,) = _createTokenInLaunchpad("test-sell-basic", "Sell Basic Token", "SELLBASIC");

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    uint256 amountToSell = 100 * 1e18;

    vm.startPrank(user1);
    IERC20(token).approve(address(uiHelper), amountToSell);
    uint256 amountSwapOut = uiHelper.sellWithExactInputWithOpenOcean{value: 0}(openOceanParams, IERC20(token), amountToSell, 0);
    vm.stopPrank();

    assertEq(amountSwapOut, adapter.mockSwapAmountOut());
  }

  function test_sellWithExactInputWithOpenOcean_withOpenOceanData() public {
    (address token,) = _createTokenInLaunchpad("test-sell-openocean", "Sell OpenOcean Token", "SELLOPENOCEAN");

    // Set up mock OpenOcean output
    openOcean.setMockOutput(address(fundingToken), 100 * 1e18);

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: fundingToken,
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](1)
    });

    uint256 amountToSell = 100 * 1e18;

    vm.startPrank(user1);
    IERC20(token).approve(address(uiHelper), amountToSell);
    uint256 amountSwapOut = uiHelper.sellWithExactInputWithOpenOcean{value: 0}(openOceanParams, IERC20(token), amountToSell, 0);
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

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    uint256 initialBalance = user1.balance;

    vm.prank(user1);
    uiHelper.createAndBuy(openOceanParams, params, address(0), 0);

    // Check that ETH was purged (sent back to user)
    assertEq(user1.balance, initialBalance + 1 ether);
    assertEq(address(uiHelper).balance, 0);
  }



  // ============ Error Cases Tests ============

  function test_openOcean_call_failure() public {
    // Set OpenOcean to revert on calls
    openOcean.setShouldRevertOnCall(true);

    (address token,) = _createTokenInLaunchpad("test-openocean-fail", "OpenOcean Fail Token", "OPENOCEANFAIL");

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](1)
    });

    vm.prank(user1);
    vm.expectRevert(IUIHelper.OpenOceanCallFailed.selector);
    uiHelper.buyWithExactInputWithOpenOcean{value: 0}(openOceanParams, IERC20(token), 0, 0);
  }

  // ============ Receive Ether Test ============

  function test_receive_ether() public {
    // Test that UIHelper can receive ETH
    (bool success,) = address(uiHelper).call{value: 1 ether}("");
    assertTrue(success);
    assertEq(address(uiHelper).balance, 1 ether);
  }

  // ============ Fuzz Tests ============

  function test_fuzz_buyWithExactInputWithOpenOcean(uint256 tokenAmount) public {
    // Bound the amount to reasonable values
    tokenAmount = bound(tokenAmount, 1 * 1e18, 1000 * 1e18);

    // First create a token in the launchpad so claimFees works
    (address token,) = _createTokenInLaunchpad("fuzz-buy", "Fuzz Buy Token", "FUZZBUY");

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: fundingToken,
      tokenAmountIn: tokenAmount,
      tokenOut: fundingToken,
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    vm.startPrank(user1);
    fundingToken.approve(address(uiHelper), tokenAmount);
    uint256 amountOut = uiHelper.buyWithExactInputWithOpenOcean(openOceanParams, IERC20(token), 0, 0);
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

      IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
        tokenIn: IERC20(address(0)),
        tokenAmountIn: 0,
        tokenOut: fundingToken,
        minReturnAmount: 0,
        guaranteedAmount: 0,
        flags: 0,
        referrer: address(0),
        permit: "",
        calls: new IOpenOceanCaller.CallDescription[](0)
      });

      vm.prank(user1);
      (address token,,, uint256 tokenId) = uiHelper.createAndBuy(openOceanParams, params, address(0), 0);

      assertTrue(token != address(0));
      assertEq(launchpad.ownerOf(tokenId), user1);
    }

    assertEq(launchpad.getTotalTokens(), 3);
  }

  function test_multiple_buyWithExactInputWithOpenOcean() public {
    // Create a token first
    (address token,) = _createTokenInLaunchpad("multi-buy", "Multi Buy Token", "MULTIBUY");

    // Perform multiple buy operations
    for (uint256 i = 0; i < 3; i++) {
      IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
        tokenIn: fundingToken,
        tokenAmountIn: 100 * 1e18,
        tokenOut: fundingToken,
        minReturnAmount: 0,
        guaranteedAmount: 0,
        flags: 0,
        referrer: address(0),
        permit: "",
        calls: new IOpenOceanCaller.CallDescription[](0)
      });

      vm.startPrank(user1);
      fundingToken.approve(address(uiHelper), 100 * 1e18);
      uint256 amountOut = uiHelper.buyWithExactInputWithOpenOcean(openOceanParams, IERC20(token), 0, 0);
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

    IUIHelper.OpenOceanParams memory openOceanParams = IUIHelper.OpenOceanParams({
      tokenIn: IERC20(address(0)),
      tokenAmountIn: 0,
      tokenOut: IERC20(address(0)),
      minReturnAmount: 0,
      guaranteedAmount: 0,
      flags: 0,
      referrer: address(0),
      permit: "",
      calls: new IOpenOceanCaller.CallDescription[](0)
    });

    vm.prank(user1);
    (address token,,, uint256 tokenId) = uiHelper.createAndBuy(openOceanParams, params, address(0), 0);

    assertTrue(token != address(0));
    assertEq(launchpad.ownerOf(tokenId), user1);
  }
}
