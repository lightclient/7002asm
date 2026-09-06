// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

address constant addr = 0x0000000000000000000000000000000000008272;

// EIP-8272 recent-root predeploy.
//
// The write path reads the beacon slot with the EIP-7843 SLOTNUM opcode (0x4b),
// which is not available under this repo's `prague` EVM, so the shipped runtime
// cannot be exercised directly here. The guard tests below run the shipped
// runtime and cover the calldata guard, whose reverts all halt before SLOTNUM is
// reached. The write-path test runs a slot-shimmed build of the same source
// (test/recent_root_slotnum1.eas, SLOTNUM -> push1 0x01) so the derivation and
// SSTORE can be checked against EIP-8272's published Reference vector. The real
// SLOTNUM opcode itself is exercised on an EIP-7843 EVM at the client level and
// end to end on the two-client devnet.
contract RecentRootTest is Test {
    address unit;

    function setUp() public {
        vm.etch(addr, vm.parseBytes(vm.readFile("bytecode/recent_root/main.hex")));
        unit = addr;
    }

    // A well-shaped write is salt(32) || root(32); a nonzero call value must be rejected.
    function testRejectsNonzeroValue() public {
        vm.deal(address(this), 1 ether);
        bytes memory data = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)));
        (bool ret,) = unit.call{value: 1}(data);
        assertFalse(ret);
    }

    // Any calldata length other than 64 bytes must be rejected.
    function testRejectsBadCalldataSize() public {
        (bool ret,) = unit.call(hex"");
        assertFalse(ret);

        // 63 bytes
        (ret,) = unit.call(new bytes(63));
        assertFalse(ret);

        // 65 bytes
        (ret,) = unit.call(new bytes(65));
        assertFalse(ret);
    }

    // Full write path against EIP-8272's published Reference vector (current_slot = 2):
    //   source_address = 0x..01, salt = 0, slot = 1, root = 2
    //   storage_key    = 0x5f027aa1..., entry_hash = 0x0a0d1254...
    // Runs the slot-shimmed build so it executes under prague; the shim fixes the
    // slot to 1 in place of SLOTNUM, matching the vector's slot.
    function testWritePathMatchesReferenceVector() public {
        address shim = address(uint160(uint256(keccak256("recent-root-slotnum1-shim"))));
        vm.etch(shim, vm.parseBytes(vm.readFile("test/recent_root_slotnum1.hex")));

        bytes memory data = abi.encodePacked(bytes32(0), bytes32(uint256(2)));
        vm.prank(address(0x01));
        (bool ok,) = shim.call(data);
        assertTrue(ok);

        bytes32 storageKey = 0x5f027aa1cbe2df279bf6518edd4b44ea5409fd800189ec35224e10ab05e574c3;
        bytes32 entryHash = 0x0a0d1254c851be5a133b4c9a9e300f5602fc0f43dbe65aa6a66930d4ca0a51b8;
        assertEq(vm.load(shim, storageKey), entryHash);

        // Nothing lands at any other key: the untouched neighbour index is zero.
        bytes32 otherKey = keccak256("some-unrelated-slot");
        assertEq(vm.load(shim, otherKey), bytes32(0));
    }
}
