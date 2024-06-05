// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

address constant fakeExpo = 0x000000000000000000000000000000000000BbBB;
address constant addr = 0x000000000000000000000000000000000000aaaa;
address constant sysaddr = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;

uint256 constant excess_slot = 0;
uint256 constant count_slot   = 1;
uint256 constant queue_head_slot   = 2;
uint256 constant queue_tail_slot   = 3;
uint256 constant queue_storage_offset = 4;

abstract contract TestHelper is Test {

  function min(uint256 x, uint256 y) internal pure returns (uint256) {
    if (x < y) {
      return x;
    }
    return y;
  }

  function addFailedRequest(address from, bytes memory req, uint256 value) internal {
    vm.deal(from, value);
    vm.prank(from);
    (bool ret,) = addr.call{value: value}(req);
    assertEq(ret, false, "expected request to fail");
  }

  // getRequests will simulate a system call to the system contract.
  function getRequests() internal returns (bytes memory) {
    vm.prank(sysaddr);
    (bool ret, bytes memory data) = addr.call("");
    assertEq(ret, true);
    return data;
  }

  function load(uint256 slot) internal view returns (uint256) {
    return uint256(vm.load(addr, bytes32(slot)));
  }

  function assertStorage(uint256 slot, uint256 value, string memory err) internal {
    bytes32 got = vm.load(addr, bytes32(slot));
    assertEq(got, bytes32(value), err);
  }

  function assertExcess(uint256 count) internal {
    assertStorage(excess_slot, count, "unexpected excess requests");
    (, bytes memory data) = addr.call("");
    assertEq(toFixed(data, 0, 32), count, "unexpected excess requests");
  }

  function toFixed(bytes memory data, uint256 start, uint256 end) internal pure returns (uint256) {
    require(end-start <= 32, "range cannot be larger than 32 bytes");
    bytes memory out = new bytes(32);
    for (uint256 i = start; i < end; i++) {
      out[i-start] = data[i];
    }
    return uint256(bytes32(out));
  }

  function computeFee(uint256 excess) internal returns (uint256) {
    return callFakeExpo(1, int(excess), 17);
  }

  function callFakeExpo(int factor, int numerator, int denominator) internal returns (uint256) {
    (, bytes memory data) = fakeExpo.call(bytes.concat(bytes32(uint256(factor)), bytes32(uint256(numerator)), bytes32(uint256(denominator))));
    return toFixed(data, 0, 32);
  }
}
