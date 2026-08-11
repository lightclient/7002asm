// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Test.sol";

uint256 constant target_per_block = 1;
uint256 constant max_per_block = 4;
uint256 constant inhibitor = uint256(bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff));

uint256 constant slots_per_item = 7;

contract PreregistrationTest is Test {
  function setUp() public {
    vm.etch(addr, vm.parseBytes(vm.readFile("bytecode/preregistrations/main.hex")));
    vm.etch(fakeExpo, vm.parseBytes(vm.readFile("bytecode/fake_expo_test/main.hex")));
  }

  // testConstructor verifies the deployment code installs the expected runtime
  // and sets the pre-fork inhibitor.
  function testConstructor() public {
    bytes memory initcode = vm.parseBytes(vm.readFile("bytecode/preregistrations/ctor.hex"));
    bytes memory runtime = vm.parseBytes(vm.readFile("bytecode/preregistrations/main.hex"));
    address deployed;
    assembly {
      deployed := create(0, add(initcode, 32), mload(initcode))
    }

    assertTrue(deployed != address(0), "deployment failed");
    assertEq(deployed.code, runtime, "unexpected runtime code");
    assertEq(vm.load(deployed, bytes32(excess_slot)), bytes32(inhibitor), "expected inhibitor");

    vm.deal(address(this), 1);
    (bool ret,) = deployed.call{value: 1}(makePreregistration(0));
    assertEq(ret, false, "request must fail before activation");

    vm.prank(sysaddr);
    (ret,) = deployed.call("");
    assertEq(ret, true, "activation system call failed");
    assertEq(vm.load(deployed, bytes32(excess_slot)), bytes32(0), "expected inhibitor reset");
  }

  // testInvalidRequest checks that common invalid preregistration requests are
  // rejected.
  function testInvalidRequest() public {
    bytes memory req = makePreregistration(0);

    // input too small
    (bool ret,) = addr.call{value: 1e18}(hex"1234");
    assertEq(ret, false);

    // input one byte short (175 bytes)
    (ret,) = addr.call{value: 1e18}(slice(req, 0, 175));
    assertEq(ret, false);

    // input one byte long (177 bytes)
    (ret,) = addr.call{value: 1e18}(bytes.concat(req, hex"00"));
    assertEq(ret, false);

    // ABI-style call (4-byte selector prefix)
    (ret,) = addr.call{value: 1e18}(bytes.concat(hex"deadbeef", req));
    assertEq(ret, false);

    // fee too small
    (ret,) = addr.call{value: 0}(req);
    assertEq(ret, false);

    assertStorage(count_slot, 0, "expected no requests enqueued");
  }

  // testPreregistration verifies a single preregistration request below the
  // target request count is accepted and read successfully.
  function testPreregistration() public {
    bytes memory data = makePreregistration(0x11);

    // The record (caller ++ input) is emitted verbatim as an anonymous log.
    bytes memory record = bytes.concat(bytes20(address(this)), data);
    vm.expectEmitAnonymous(false, false, false, false, true);
    assembly {
      log0(add(record, 32), mload(record))
    }

    (bool ret,) = addr.call{value: 2}(data);
    assertEq(ret, true, "call failed");
    assertStorage(count_slot, 1, "unexpected request count");
    assertExcess(0);

    bytes memory req = getRequests();
    assertEq(req.length, 196);
    assertEq(req, record, "unexpected record");
    assertStorage(count_slot, 0, "unexpected request count");
    assertStorage(queue_head_slot, 0, "expected queue head reset");
    assertStorage(queue_tail_slot, 0, "expected queue tail reset");
    assertExcess(0);
    assertEq(addr.balance, 2, "fee overpayment should be retained");
  }

  // testQueueReset verifies that after a period with more requests than can be
  // read per block, the queue is eventually cleared and the head and tail are
  // reset to zero.
  function testQueueReset() public {
    // Add more requests than the max per block (4) so that the queue is not
    // immediately emptied.
    for (uint256 i = 0; i < max_per_block+1; i++) {
      addRequest(address(uint160(i)), makePreregistration(i), 2);
    }
    assertStorage(count_slot, max_per_block+1, "unexpected request count");

    // Simulate syscall, check that max requests per block are read.
    checkPreregistrations(0, max_per_block);
    assertExcess(4);

    // Add another batch of max requests per block (4) so the next read leaves a
    // single request in the queue.
    for (uint256 i = 5; i < 5 + max_per_block; i++) {
      addRequest(address(uint160(i)), makePreregistration(i), 2);
    }
    assertStorage(count_slot, max_per_block, "unexpected request count");

    // Simulate syscall. Verify first that max per block are read. Then
    // verify only the single final request is read.
    checkPreregistrations(4, max_per_block);
    assertExcess(7);
    checkPreregistrations(8, 1);
    assertExcess(6);

    // Now ensure the queue is empty and has reset to zero.
    assertStorage(queue_head_slot, 0, "expected queue head reset");
    assertStorage(queue_tail_slot, 0, "expected queue tail reset");

    // Add five (5) more requests to check that new requests can be added after
    // the queue is reset.
    for (uint256 i = 9; i < 14; i++) {
      addRequest(address(uint160(i)), makePreregistration(i), 4);
    }
    assertStorage(count_slot, 5, "unexpected request count");

    // Simulate syscall, read only the max requests per block.
    checkPreregistrations(9, max_per_block);
    assertExcess(10);
  }

  // testFee adds many requests and verifies the excess decreases correctly until
  // it returns to 0 and the fee returns to its floor.
  function testFee() public {
    uint256 idx = 0;
    uint256 count = max_per_block*64;

    // Add a bunch of requests.
    for (; idx < count; idx++) {
      addRequest(address(uint160(idx)), makePreregistration(idx), 1);
    }
    assertStorage(count_slot, count, "unexpected request count");
    checkPreregistrations(0, max_per_block);

    uint256 read = max_per_block;
    uint256 excess = count - target_per_block;

    // Attempt to add an invalid request with fee too low or a valid request.
    // This should cause the excess requests counter to either decrease by 1
    // or remain the same each iteration.
    for (uint256 i = 0; i < count; i++) {
      assertExcess(excess);

      uint256 fee = computeFee(excess);
      bool success = (i % 2 == 0);
      if (success) {
        addRequest(address(uint160(idx)), makePreregistration(idx), fee);
        // Bump index when a new request is created.
        idx++;
      } else {
        addFailedRequest(address(uint160(idx)), makePreregistration(idx), fee-1);
      }

      uint256 queue_size = idx - read;
      uint256 expected = min(queue_size, max_per_block);
      checkPreregistrations(read, expected);

      if (excess > 0 && !success) {
        excess--;
      }
      read += expected;
    }

    // The queue is now empty. Simulate empty blocks (a failed request, then a
    // syscall) and verify the excess decays by one per block until it returns
    // to 0 and the fee is back at the floor.
    while (excess > 0) {
      uint256 fee = computeFee(excess);
      addFailedRequest(address(uint160(idx)), makePreregistration(idx), fee-1);

      bytes memory requests = getRequests();
      assertEq(requests.length, 0, "expected empty queue");

      excess--;
      assertExcess(excess);
    }

    // With the excess fully decayed, a request at the minimum fee is accepted.
    addRequest(address(uint160(idx)), makePreregistration(idx), 1);
  }

  // testFeeGetterRejectsValue verifies the empty-calldata fee getter reverts
  // when value is attached, preventing accidental loss of funds.
  function testFeeGetterRejectsValue() public {
    vm.deal(address(this), 1);
    (bool ret,) = addr.call{value: 1}("");
    assertEq(ret, false, "fee getter must reject callvalue");
  }

  // testFeeGetter checks the fee getter against fixed vectors independent of the
  // shared fake exponentiation test contract.
  function testFeeGetter() public {
    uint256[5] memory excesses = [uint256(0), 16, 32, 64, 100];
    uint256[5] memory fees = [uint256(1), 2, 6, 42, 357];

    for (uint256 i = 0; i < excesses.length; i++) {
      vm.store(addr, bytes32(excess_slot), bytes32(excesses[i]));
      (bool ret, bytes memory data) = addr.staticcall("");
      assertEq(ret, true, "fee getter failed");
      assertEq(data.length, 32, "unexpected fee getter output length");
      assertEq(uint256(bytes32(data)), fees[i], "unexpected fee");
      assertStorage(excess_slot, excesses[i], "fee getter modified storage");
    }
  }

  // testInhibitorReset verifies that after the first system call the excess
  // value is reset to 0.
  function testInhibitorReset() public {
    vm.store(addr, bytes32(0), bytes32(inhibitor));
    vm.prank(sysaddr);
    (bool ret, bytes memory data) = addr.call("");
    assertEq(ret, true, "system call failed");
    assertEq(data.length, 0, "expected no requests");
    assertStorage(excess_slot, 0, "expected excess requests to be reset");

    vm.store(addr, bytes32(0), bytes32(inhibitor));
    addFailedRequest(address(uint160(0)), makePreregistration(0), inhibitor);

    vm.store(addr, bytes32(0), bytes32(inhibitor-1));
    vm.prank(sysaddr);
    (ret, data) = addr.call("");
    assertEq(ret, true, "system call failed");
    assertEq(data.length, 0, "expected no requests");
    assertStorage(excess_slot, inhibitor-target_per_block-1, "didn't expect excess to be reset");
  }

  // --------------------------------------------------------------------------
  // helpers ------------------------------------------------------------------
  // --------------------------------------------------------------------------

  // addRequest will submit a request to the system contract with the given values.
  function addRequest(address from, bytes memory req, uint256 value) internal {
    // Load tail index before adding request.
    uint256 requests = load(count_slot);
    uint256 tail = load(queue_tail_slot);

    // Send request from address.
    vm.deal(from, value);
    vm.prank(from);
    (bool ret,) = addr.call{value: value}(req);
    assertEq(ret, true, "expected call to succeed");

    // Verify the queue data was updated correctly.
    assertStorage(count_slot, requests+1, "unexpected request count");
    assertStorage(queue_tail_slot, tail+1, "unexpected tail slot");

    // Verify the request was written to the queue.
    uint256 idx = queue_storage_offset+tail*slots_per_item;
    assertStorage(idx,   uint256(uint160(from)), "addr not written to queue");
    assertStorage(idx+1, toFixed(req, 0, 32),    "pk[0:32] not written to queue");
    assertStorage(idx+2, toFixed(req, 32, 64),   "pk[32:48] ++ wc[0:16] not written to queue");
    assertStorage(idx+3, toFixed(req, 64, 96),   "wc[16:32] ++ sig[0:16] not written to queue");
    assertStorage(idx+4, toFixed(req, 96, 128),  "sig[16:48] not written to queue");
    assertStorage(idx+5, toFixed(req, 128, 160), "sig[48:80] not written to queue");
    assertStorage(idx+6, toFixed(req, 160, 176), "sig[80:96] not written to queue");
  }

  // checkPreregistrations will simulate a system call to the system contract
  // and verify the expected preregistration requests are returned.
  //
  // It assumes that addresses are stored as uint256(index) and requests were
  // created with makePreregistration.
  function checkPreregistrations(uint256 startIndex, uint256 count) internal returns (uint256) {
    bytes memory requests = getRequests();
    assertEq(requests.length, count*196);
    for (uint256 i = 0; i < count; i++) {
      uint256 offset = i*196;
      assertEq(toFixed(requests, offset, offset+20) >> 96, uint256(startIndex+i), "unexpected request address returned");
      assertEq(slice(requests, offset+20, 176), makePreregistration(startIndex+i), "unexpected request record returned");
    }
    return count;
  }

  // makePreregistration constructs a preregistration request with a base of x.
  // Every byte is position-dependent (uint8(x+i)) so that every 32-byte chunk
  // of the request is unique and chunk-order or offset bugs in the contract
  // cannot cancel out against a uniform fill.
  function makePreregistration(uint256 x) internal pure returns (bytes memory) {
    bytes memory out = new bytes(176);
    for (uint256 i = 0; i < 176; i++) {
      out[i] = bytes1(uint8(x+i));
    }
    return out;
  }
}
