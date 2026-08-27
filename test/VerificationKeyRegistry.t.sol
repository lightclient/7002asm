// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

address constant registry = 0x0000000000000000000000000000000000008357;
address constant systemAddress = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
address constant user = 0x0000000000000000000000000000000000001234;

bytes32 constant K1 = bytes32(uint256(1));
bytes32 constant K2 = bytes32(uint256(2));
bytes32 constant K3 = bytes32(uint256(3));
uint256 constant T1 = 1;
uint256 constant T2 = type(uint64).max;

contract VerificationKeyRegistryTest is Test {
    mapping(bytes32 => uint256) internal modelActivation;
    bytes32 internal modelCurrent;

    function setUp() public {
        vm.etch(registry, vm.parseBytes(vm.readFile("bytecode/verification_key_registry/main.hex")));
    }

    function activationSlot(bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, uint256(1)));
    }

    function callRegistry(address from, bytes memory input, uint256 value) internal returns (bool, bytes memory) {
        vm.deal(from, value);
        vm.prank(from);
        return registry.call{value: value}(input);
    }

    function register(bytes32 key, uint256 timestamp) internal returns (bool, bytes memory) {
        return callRegistry(systemAddress, abi.encodePacked(key, bytes32(timestamp)), 0);
    }

    function reactivate(bytes32 key) internal returns (bool, bytes memory) {
        return callRegistry(systemAddress, abi.encodePacked(key), 0);
    }

    function read(bytes32 key) internal returns (bool, bytes memory) {
        return callRegistry(user, abi.encodePacked(key), 0);
    }

    function assertModelState() internal view {
        assertEq(vm.load(registry, bytes32(uint256(0))), modelCurrent);
        for (uint256 i = 0; i <= 4; i++) {
            bytes32 key = bytes32(i);
            assertEq(vm.load(registry, activationSlot(key)), bytes32(modelActivation[key]));
        }
    }

    function testConstructor() public {
        bytes memory initcode = vm.parseBytes(vm.readFile("bytecode/verification_key_registry/ctor.hex"));
        bytes memory runtime = vm.parseBytes(vm.readFile("bytecode/verification_key_registry/main.hex"));

        address deployed;
        assembly {
            deployed := create(0, add(initcode, 32), mload(initcode))
        }

        assertNotEq(deployed, address(0));
        assertEq(deployed.code, runtime);
        assertEq(runtime.length, 165);
        assertEq(initcode.length, 174);
        assertEq(keccak256(runtime), 0xd55eb0472aba968311f3ee6dca96e029d22b0d70d20890a6e842ffd0074c0829);
        assertEq(keccak256(initcode), 0xbabcba375309459d1b777dde3ca61dde2935df82b668e4bfbe55963fd8f82fe8);
        assertEq(deployed.code.length, 165);
        assertEq(deployed.balance, 0);
        assertEq(deployed.codehash, keccak256(runtime));
        assertEq(vm.load(deployed, bytes32(uint256(0))), bytes32(0));
    }

    function testRegisterAndReadCurrentOrExplicitKey() public {
        (bool ok, bytes memory output) = read(bytes32(0));
        assertFalse(ok);
        assertEq(output, hex"");

        (ok, output) = register(K1, T1);
        assertTrue(ok);
        assertEq(output, hex"");

        assertEq(vm.load(registry, bytes32(uint256(0))), K1);
        assertEq(vm.load(registry, activationSlot(K1)), bytes32(T1));

        (ok, output) = read(bytes32(0));
        assertTrue(ok);
        assertEq(output, abi.encodePacked(K1, bytes32(T1)));

        (ok, output) = read(K1);
        assertTrue(ok);
        assertEq(output, abi.encodePacked(K1, bytes32(T1)));

        (ok, output) = read(K2);
        assertFalse(ok);
        assertEq(output, hex"");
    }

    function testRegistrationBoundsAndUniqueness() public {
        (bool ok,) = register(bytes32(0), T1);
        assertFalse(ok);

        (ok,) = register(K1, 0);
        assertFalse(ok);

        (ok,) = register(K1, T1);
        assertTrue(ok);

        (ok,) = register(K1, T2);
        assertFalse(ok);
        assertEq(vm.load(registry, activationSlot(K1)), bytes32(T1));

        (ok,) = register(K2, T2);
        assertTrue(ok);
        assertEq(vm.load(registry, activationSlot(K2)), bytes32(T2));

        (ok,) = register(K3, uint256(type(uint64).max) + 1);
        assertFalse(ok);
        assertEq(vm.load(registry, activationSlot(K3)), bytes32(0));
    }

    function testReactivateRegisteredKey() public {
        (bool ok,) = register(K1, T1);
        assertTrue(ok);
        (ok,) = register(K2, T2);
        assertTrue(ok);
        assertEq(vm.load(registry, bytes32(uint256(0))), K2);

        (ok,) = reactivate(K1);
        assertTrue(ok);
        assertEq(vm.load(registry, bytes32(uint256(0))), K1);
        assertEq(vm.load(registry, activationSlot(K1)), bytes32(T1));
        assertEq(vm.load(registry, activationSlot(K2)), bytes32(T2));

        (ok,) = reactivate(bytes32(0));
        assertFalse(ok);
        (ok,) = reactivate(K3);
        assertFalse(ok);
        assertEq(vm.load(registry, bytes32(uint256(0))), K1);
    }

    function testRejectsInvalidCalldataLengths() public {
        uint256[6] memory invalidReadLengths = [uint256(0), 1, 31, 33, 63, 64];
        for (uint256 i = 0; i < invalidReadLengths.length; i++) {
            (bool ok, bytes memory output) = callRegistry(user, new bytes(invalidReadLengths[i]), 0);
            assertFalse(ok);
            assertEq(output, hex"");
        }

        uint256[6] memory invalidUpdateLengths = [uint256(0), 1, 31, 33, 63, 65];
        for (uint256 i = 0; i < invalidUpdateLengths.length; i++) {
            (bool ok, bytes memory output) = callRegistry(systemAddress, new bytes(invalidUpdateLengths[i]), 0);
            assertFalse(ok);
            assertEq(output, hex"");
        }
    }

    function testRejectsNonzeroValue() public {
        (bool ok, bytes memory output) = callRegistry(user, abi.encodePacked(K1), 1);
        assertFalse(ok);
        assertEq(output, hex"");

        (ok, output) = callRegistry(systemAddress, abi.encodePacked(K1, bytes32(T1)), 1);
        assertFalse(ok);
        assertEq(output, hex"");
        assertEq(registry.balance, 0);
        assertEq(vm.load(registry, bytes32(uint256(0))), bytes32(0));
    }

    function testStorageWritesAreScoped() public {
        vm.record();
        (bool ok,) = register(K1, T1);
        assertTrue(ok);
        (, bytes32[] memory writes) = vm.accesses(registry);
        assertEq(writes.length, 2);
        assertEq(writes[0], activationSlot(K1));
        assertEq(writes[1], bytes32(uint256(0)));

        vm.record();
        (ok,) = reactivate(K1);
        assertTrue(ok);
        (, writes) = vm.accesses(registry);
        assertEq(writes.length, 1);
        assertEq(writes[0], bytes32(uint256(0)));

        vm.record();
        (ok,) = read(bytes32(0));
        assertTrue(ok);
        (, writes) = vm.accesses(registry);
        assertEq(writes.length, 0);

        vm.record();
        (ok,) = register(K1, T2);
        assertFalse(ok);
        (, writes) = vm.accesses(registry);
        assertEq(writes.length, 0);
    }

    function testFuzzRegisterAndRead(bytes32 key, uint64 timestamp) public {
        vm.assume(key != bytes32(0));
        vm.assume(timestamp != 0);

        (bool ok,) = register(key, timestamp);
        assertTrue(ok);

        bytes memory output;
        (ok, output) = read(bytes32(0));
        assertTrue(ok);
        assertEq(output, abi.encodePacked(key, bytes32(uint256(timestamp))));
        assertEq(vm.load(registry, activationSlot(key)), bytes32(uint256(timestamp)));
    }

    function testFuzzStateMachine(bytes32 seed) public {
        for (uint256 i = 0; i < 24; i++) {
            uint256 word = uint256(keccak256(abi.encode(seed, i)));
            bytes32 key = bytes32(word % 5);
            uint256 timestampChoice = (word >> 8) % 5;
            uint256 timestamp;
            if (timestampChoice == 1) {
                timestamp = 1;
            } else if (timestampChoice == 2) {
                timestamp = type(uint64).max;
            } else if (timestampChoice == 3) {
                timestamp = uint256(type(uint64).max) + 1;
            } else if (timestampChoice == 4) {
                timestamp = word;
            }

            uint256 action = (word >> 16) % 6;
            bool expected;
            bool ok;
            bytes memory output;

            if (action == 0) {
                expected =
                    key != bytes32(0) && timestamp != 0 && timestamp <= type(uint64).max && modelActivation[key] == 0;
                (ok, output) = register(key, timestamp);
                assertEq(ok, expected);
                assertEq(output, hex"");
                if (expected) {
                    modelActivation[key] = timestamp;
                    modelCurrent = key;
                }
            } else if (action == 1) {
                expected = key != bytes32(0) && modelActivation[key] != 0;
                (ok, output) = reactivate(key);
                assertEq(ok, expected);
                assertEq(output, hex"");
                if (expected) {
                    modelCurrent = key;
                }
            } else if (action == 2) {
                bytes32 selectedKey = key == bytes32(0) ? modelCurrent : key;
                expected = selectedKey != bytes32(0) && modelActivation[selectedKey] != 0;
                (ok, output) = read(key);
                assertEq(ok, expected);
                bytes memory expectedOutput;
                if (expected) {
                    expectedOutput = abi.encodePacked(selectedKey, bytes32(modelActivation[selectedKey]));
                }
                assertEq(output, expectedOutput);
            } else if (action == 3) {
                expected = modelCurrent != bytes32(0);
                (ok, output) = read(bytes32(0));
                assertEq(ok, expected);
                bytes memory expectedOutput;
                if (expected) {
                    expectedOutput = abi.encodePacked(modelCurrent, bytes32(modelActivation[modelCurrent]));
                }
                assertEq(output, expectedOutput);
            } else if (action == 4) {
                address from = ((word >> 24) & 1) == 0 ? user : systemAddress;
                uint256 invalidLength = ((word >> 25) & 1) == 0 ? 31 : 33;
                (ok, output) = callRegistry(from, new bytes(invalidLength), 0);
                assertFalse(ok);
                assertEq(output, hex"");
            } else {
                address from = ((word >> 24) & 1) == 0 ? user : systemAddress;
                bytes memory input =
                    from == systemAddress ? abi.encodePacked(key, bytes32(timestamp)) : abi.encodePacked(key);
                (ok, output) = callRegistry(from, input, 1);
                assertFalse(ok);
                assertEq(output, hex"");
                assertEq(registry.balance, 0);
            }

            assertModelState();
        }
    }
}
