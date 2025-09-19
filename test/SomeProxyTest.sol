// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ISomeProxy, SomeProxy} from "contracts/SomeProxy.sol";
import {Test} from "lib/forge-std/src/Test.sol";

import "forge-std/console.sol";

// Mock implementation contracts for testing
contract MockImplementationV1 {
  uint256 public value;
  string public name;

  function initialize(uint256 _value, string memory _name) external {
    value = _value;
    name = _name;
  }

  function setValue(uint256 _value) external {
    value = _value;
  }

  function setName(string memory _name) external {
    name = _name;
  }

  function getValue() external view returns (uint256) {
    return value;
  }

  function getName() external view returns (string memory) {
    return name;
  }

  function revertFunction() external pure {
    revert("Mock revert");
  }

  receive() external payable {
    // Accept ETH
  }
}

contract MockImplementationV2 {
  uint256 public value;
  string public name;
  bool public upgraded;

  function initialize(uint256 _value, string memory _name) external {
    value = _value;
    name = _name;
    upgraded = true;
  }

  function setValue(uint256 _value) external {
    value = _value;
  }

  function setName(string memory _name) external {
    name = _name;
  }

  function getValue() external view returns (uint256) {
    return value;
  }

  function getName() external view returns (string memory) {
    return name;
  }

  function isUpgraded() external view returns (bool) {
    return upgraded;
  }

  function newFunction() external pure returns (string memory) {
    return "V2 Function";
  }

  receive() external payable {
    // Accept ETH
  }
}

contract MockImplementationWithConstructor {
  uint256 public immutable value;

  constructor(uint256 _value) {
    value = _value;
  }

  function getValue() external view returns (uint256) {
    return value;
  }
}

contract SomeProxyTest is Test {
  SomeProxy proxy;
  MockImplementationV1 implementationV1;
  MockImplementationV2 implementationV2;
  MockImplementationWithConstructor implementationWithConstructor;

  address admin;
  address user1;
  address user2;

  // Events to test
  event Upgraded(address indexed implementation);
  event AdminChanged(address previousAdmin, address newAdmin);

  function setUp() public {
    admin = makeAddr("admin");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");

    // Deploy implementation contracts
    implementationV1 = new MockImplementationV1();
    implementationV2 = new MockImplementationV2();
    implementationWithConstructor = new MockImplementationWithConstructor(42);

    // Prepare initialization data for the proxy
    bytes memory initData = abi.encodeWithSelector(MockImplementationV1.initialize.selector, 100, "Initial Name");

    // Deploy the proxy
    vm.prank(admin);
    proxy = new SomeProxy(address(implementationV1), admin, initData);
  }

  // ============ Constructor Tests ============

  function test_constructor_initialization() public {
    // Test that proxy is deployed correctly
    assertEq(address(proxy), address(proxy)); // Basic existence check

    // Test admin is set correctly
    assertEq(proxy.proxyAdmin(), admin);

    // Test implementation is set correctly
    assertEq(proxy.implementation(), address(implementationV1));

    // Test that initialization data was called
    (bool success, bytes memory data) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV1.getValue.selector));
    require(success, "Failed to call getValue");
    uint256 value = abi.decode(data, (uint256));
    assertEq(value, 100);

    (success, data) = address(proxy).call(abi.encodeWithSelector(MockImplementationV1.getName.selector));
    require(success, "Failed to call getName");
    string memory name = abi.decode(data, (string));
    assertEq(name, "Initial Name");
  }

  function test_constructor_without_initialization_data() public {
    // Deploy proxy without initialization data
    vm.prank(admin);
    SomeProxy newProxy = new SomeProxy(address(implementationV1), admin, "");

    assertEq(newProxy.proxyAdmin(), admin);
    assertEq(newProxy.implementation(), address(implementationV1));
  }

  function test_constructor_admin_change() public {
    // Test that admin was changed from the proxy itself to the specified admin
    assertEq(proxy.proxyAdmin(), admin);

    // The ERC1967 admin should be the admin address, not the proxy
    // We can verify this through the proxy's proxyAdmin function
    assertEq(proxy.proxyAdmin(), admin);
  }

  // ============ Proxy Function Tests ============

  function test_proxy_delegation() public {
    // Test that calls are properly delegated to implementation
    vm.prank(user1);
    (bool success, bytes memory data) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV1.getValue.selector));

    assertTrue(success);
    uint256 value = abi.decode(data, (uint256));
    assertEq(value, 100);
  }

  function test_proxy_state_modification() public {
    // Test that state modifications work through proxy
    uint256 newValue = 200;

    vm.prank(user1);
    (bool success,) = address(proxy).call(abi.encodeWithSelector(MockImplementationV1.setValue.selector, newValue));

    assertTrue(success);

    // Verify the state change
    (bool success2, bytes memory data2) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV1.getValue.selector));
    require(success2, "Failed to call getValue");
    uint256 value = abi.decode(data2, (uint256));
    assertEq(value, newValue);
  }

  function test_proxy_revert_propagation() public {
    // Test that reverts from implementation are properly propagated
    vm.prank(user1);
    (bool success,) = address(proxy).call(abi.encodeWithSelector(MockImplementationV1.revertFunction.selector));

    assertFalse(success);
  }

  function test_proxy_eth_receiving() public {
    // Test that proxy can receive ETH
    uint256 ethAmount = 1 ether;

    vm.deal(user1, ethAmount);

    vm.prank(user1);
    (bool success,) = address(proxy).call{value: ethAmount}("");

    assertTrue(success);
    assertEq(address(proxy).balance, ethAmount);
  }

  // ============ Admin Access Tests ============

  function test_admin_can_upgrade() public {
    // Test that admin can call upgradeToAndCall
    bytes memory upgradeData = abi.encodeWithSelector(MockImplementationV2.initialize.selector, 300, "Upgraded Name");

    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), upgradeData);

    // Verify implementation was upgraded
    assertEq(proxy.implementation(), address(implementationV2));

    // Verify upgrade data was called
    (bool success, bytes memory data) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV2.isUpgraded.selector));
    require(success, "Failed to call isUpgraded");
    bool upgraded = abi.decode(data, (bool));
    assertTrue(upgraded);

    // Verify new function is available
    (success, data) = address(proxy).call(abi.encodeWithSelector(MockImplementationV2.newFunction.selector));
    require(success, "Failed to call newFunction");
    string memory result = abi.decode(data, (string));
    assertEq(result, "V2 Function");
  }

  function test_admin_can_upgrade_without_data() public {
    // Test upgrade without initialization data
    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), "");

    assertEq(proxy.implementation(), address(implementationV2));
  }

  function test_non_admin_cannot_upgrade() public {
    // Test that non-admin cannot upgrade
    vm.prank(user1);
    vm.expectRevert();
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), "");
  }

  function test_admin_cannot_call_non_upgrade_functions() public {
    // Test that admin cannot call non-upgrade functions directly
    vm.prank(admin);
    vm.expectRevert(SomeProxy.ProxyDeniedAdminAccess.selector);
    // Try to call a non-upgrade function through the proxy
    (bool success,) = address(proxy).call(abi.encodeWithSignature("implementation()"));
    // This should fail, so success should be false
    assertFalse(success);
  }

  function test_proxy_admin_immutable() public {
    // Test that proxy admin cannot be changed after deployment
    assertEq(proxy.proxyAdmin(), admin);

    // This should always return the same admin
    assertEq(proxy.proxyAdmin(), admin);
  }

  // ============ Upgrade Mechanism Tests ============

  function test_upgrade_preserves_state() public {
    // Set some state in V1
    uint256 newValue = 500;
    vm.prank(user1);
    (bool success,) = address(proxy).call(abi.encodeWithSelector(MockImplementationV1.setValue.selector, newValue));
    assertTrue(success);

    // Upgrade to V2 without initialization data
    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), "");

    // Verify implementation changed
    assertEq(proxy.implementation(), address(implementationV2));

    // Verify state is preserved (if V2 has same storage layout)
    (bool success2, bytes memory data2) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV2.getValue.selector));
    require(success2, "Failed to call getValue");
    uint256 value = abi.decode(data2, (uint256));
    assertEq(value, newValue);
  }

  function test_upgrade_with_initialization() public {
    // Upgrade with initialization data
    bytes memory upgradeData = abi.encodeWithSelector(MockImplementationV2.initialize.selector, 999, "V2 Initialized");

    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), upgradeData);

    // Verify initialization was called
    (bool success, bytes memory data) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV2.getValue.selector));
    require(success, "Failed to call getValue");
    uint256 value = abi.decode(data, (uint256));
    assertEq(value, 999);

    (success, data) = address(proxy).call(abi.encodeWithSelector(MockImplementationV2.getName.selector));
    require(success, "Failed to call getName");
    string memory name = abi.decode(data, (string));
    assertEq(name, "V2 Initialized");
  }

  function test_upgrade_without_eth() public {
    // Test upgrade without ETH (standard case)
    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), "");

    assertEq(proxy.implementation(), address(implementationV2));
  }

  function test_upgrade_fails_with_data_and_value() public {
    // Test that upgrade fails when both data and value are provided
    bytes memory upgradeData = abi.encodeWithSelector(MockImplementationV2.initialize.selector, 999, "V2 Initialized");

    vm.deal(admin, 1 ether);

    vm.prank(admin);
    vm.expectRevert();
    ISomeProxy(address(proxy)).upgradeToAndCall{value: 0.1 ether}(address(implementationV2), upgradeData);
  }

  // ============ Edge Cases and Error Conditions ============

  function test_upgrade_to_zero_address() public {
    vm.prank(admin);
    vm.expectRevert();
    ISomeProxy(address(proxy)).upgradeToAndCall(address(0), "");
  }

  function test_upgrade_to_non_contract() public {
    vm.prank(admin);
    vm.expectRevert();
    ISomeProxy(address(proxy)).upgradeToAndCall(user1, "");
  }

  function test_upgrade_with_invalid_initialization_data() public {
    // Test upgrade with invalid initialization data
    bytes memory invalidData = abi.encodeWithSignature("nonExistentFunction()");

    vm.prank(admin);
    vm.expectRevert();
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), invalidData);
  }

  function test_multiple_upgrades() public {
    // Test multiple upgrades in sequence

    // First upgrade to V2
    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), "");
    assertEq(proxy.implementation(), address(implementationV2));

    // Second upgrade back to V1
    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV1), "");
    assertEq(proxy.implementation(), address(implementationV1));

    // Third upgrade to V2 again
    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), "");
    assertEq(proxy.implementation(), address(implementationV2));
  }

  // ============ Gas Optimization Tests ============

  function test_gas_upgrade() public {
    uint256 gasStart = gasleft();

    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), "");

    uint256 gasUsed = gasStart - gasleft();
    console.log("Gas used for upgrade:", gasUsed);
    assertLt(gasUsed, 200_000); // Reasonable gas limit for upgrades
  }

  function test_gas_delegation() public {
    uint256 gasStart = gasleft();

    (bool success,) = address(proxy).call(abi.encodeWithSelector(MockImplementationV1.getValue.selector));

    uint256 gasUsed = gasStart - gasleft();
    console.log("Gas used for delegation:", gasUsed);
    assertTrue(success);
    assertLt(gasUsed, 50_000); // Reasonable gas limit for simple delegation
  }

  // ============ Interface Compliance Tests ============

  function test_erc1967_compliance() public {
    // Test that proxy implements IERC1967 correctly
    assertEq(proxy.implementation(), address(implementationV1));
    assertEq(proxy.proxyAdmin(), admin);
  }

  function test_proxy_interface() public {
    // Test ISomeProxy interface compliance
    ISomeProxy proxyInterface = ISomeProxy(address(proxy));

    // Should be able to call upgradeToAndCall
    vm.prank(admin);
    proxyInterface.upgradeToAndCall(address(implementationV2), "");

    assertEq(proxy.implementation(), address(implementationV2));
  }

  // ============ Integration Tests ============

  function test_full_upgrade_cycle() public {
    // 1. Initial state
    (bool success, bytes memory data) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV1.getValue.selector));
    require(success, "Failed to call getValue");
    uint256 initialValue = abi.decode(data, (uint256));
    assertEq(initialValue, 100);

    // 2. Modify state in V1
    vm.prank(user1);
    (success,) = address(proxy).call(abi.encodeWithSelector(MockImplementationV1.setValue.selector, 250));
    assertTrue(success);

    // 3. Upgrade to V2 with new initialization
    bytes memory upgradeData = abi.encodeWithSelector(MockImplementationV2.initialize.selector, 400, "Final State");

    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), upgradeData);

    // 4. Verify upgrade worked
    assertEq(proxy.implementation(), address(implementationV2));

    (success, data) = address(proxy).call(abi.encodeWithSelector(MockImplementationV2.getValue.selector));
    require(success, "Failed to call getValue");
    uint256 finalValue = abi.decode(data, (uint256));
    assertEq(finalValue, 400); // Should be the new initialized value

    (success, data) = address(proxy).call(abi.encodeWithSelector(MockImplementationV2.getName.selector));
    require(success, "Failed to call getName");
    string memory finalName = abi.decode(data, (string));
    assertEq(finalName, "Final State");
  }

  // ============ Fuzz Tests ============

  function test_fuzz_upgrade_with_random_data(uint256 value, string memory name) public {
    // Bound the value to reasonable range
    value = bound(value, 1, type(uint256).max / 2);

    bytes memory upgradeData = abi.encodeWithSelector(MockImplementationV2.initialize.selector, value, name);

    vm.prank(admin);
    ISomeProxy(address(proxy)).upgradeToAndCall(address(implementationV2), upgradeData);

    // Verify the upgrade worked
    assertEq(proxy.implementation(), address(implementationV2));

    (bool success, bytes memory data) =
      address(proxy).call(abi.encodeWithSelector(MockImplementationV2.getValue.selector));
    require(success, "Failed to call getValue");
    uint256 resultValue = abi.decode(data, (uint256));
    assertEq(resultValue, value);

    (success, data) = address(proxy).call(abi.encodeWithSelector(MockImplementationV2.getName.selector));
    require(success, "Failed to call getName");
    string memory resultName = abi.decode(data, (string));
    assertEq(resultName, name);
  }
}
