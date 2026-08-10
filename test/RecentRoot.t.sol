// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

address constant addr = 0x0000000000000000000000000000000000008272;

// EIP-8272 recent-root predeploy.
//
// The write path reads the beacon slot with the EIP-7843 SLOTNUM opcode (0x4b),
// which is not available under this repo's `prague` EVM, so it cannot be
// exercised here. These tests cover the calldata guard, whose reverts all halt
// before SLOTNUM is reached. The full write path (source_id / entry_hash /
// storage_key derivation and the SSTORE) is verified against an EIP-7843 EVM at
// the client level and end to end on the two-client devnet.
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
}
