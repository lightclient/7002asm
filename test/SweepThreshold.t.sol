// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Test.sol";

uint256 constant target_per_block = 2;
uint256 constant max_per_block = 16;
uint256 constant inhibitor = uint256(bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff));

uint256 constant threshold_seed = 306783378;
uint256 constant address_seed = 429496729;
uint256 constant pubkey_seed = 715827882;

contract SweepThresholdTest is Test {
    function setUp() public {
        vm.etch(addr, vm.parseBytes(vm.readFile("bytecode/sweep_thresholds/main.hex")));
        vm.etch(fakeExpo, vm.parseBytes(vm.readFile("bytecode/fake_expo_test/main.hex")));
    }

    // testInvalidRequest checks that common invalid sweep threshold requests are rejected.
    function testInvalidRequest() public {
        // Input too small.
        (bool ret,) = addr.call{value: 1e18}(hex"1234");
        assertEq(ret, false);

        // Input is 55 bytes instead of 56.
        (ret,) = addr.call{value: 1e18}(new bytes(55));
        assertEq(ret, false);

        // Fee too small.
        (ret,) = addr.call{value: 0}(new bytes(56));
        assertEq(ret, false);
    }

    // testSweepThreshold verifies a single request below the target request count
    // is accepted and read successfully.
    function testSweepThreshold() public {
        bytes memory pubkey =
            hex"65b91c7f798c4879751a238640823f21f9b0eb1411b04298d8d079da1cb8388e6efeecd4c920c41130b025aa2af1f00a";
        bytes memory data = bytes.concat(pubkey, hex"0203040506070809");
        bytes memory expected = bytes.concat(pubkey, hex"0908070605040302");

        bytes memory eventData = bytes.concat(bytes20(address(this)), data);
        vm.expectEmitAnonymous(false, false, false, false, true);
        assembly {
            log0(add(eventData, 32), mload(eventData))
        }

        (bool ret,) = addr.call{value: 2}(data);
        assertEq(ret, true);
        assertStorage(count_slot, 1, "unexpected request count");
        assertExcess(0);

        bytes memory req = getRequests();
        assertEq(req.length, 76);
        assertEq(bytes20(req), bytes20(address(this))); // address
        assertEq(toFixed(req, 20, 52), toFixed(expected, 0, 32)); // pubkey[0:32]
        assertEq(toFixed(req, 52, 68), toFixed(expected, 32, 48)); // pubkey[32:48]
        assertEq(toFixed(req, 68, 76), toFixed(expected, 48, 56)); // threshold
        assertStorage(count_slot, 0, "unexpected request count");
        assertExcess(0);
    }

    // testQueueReset verifies that a queue spanning multiple blocks is eventually
    // cleared and its head and tail indexes are reset to zero.
    function testQueueReset() public {
        for (uint256 i = 0; i < max_per_block + 1; i++) {
            addRequest(nextAddress(i), makeSweepThreshold(i), 2);
        }
        assertStorage(count_slot, 17, "unexpected block request count");
        assertStorage(queue_head_slot, 0, "unexpected queue head");
        assertStorage(queue_tail_slot, 17, "unexpected queue tail");

        checkSweepThresholds(0, max_per_block);
        assertStorage(count_slot, 0, "expected block request count reset");
        assertStorage(queue_head_slot, 16, "unexpected queue head");
        assertStorage(queue_tail_slot, 17, "unexpected queue tail");
        assertExcess(15);

        checkSweepThresholds(16, 1);
        assertStorage(queue_head_slot, 0, "expected queue head reset");
        assertStorage(queue_tail_slot, 0, "expected queue tail reset");
        assertExcess(13);
    }

    // testFee adds many requests and verifies that the fee decreases correctly
    // until it returns to the minimum fee.
    function testFee() public {
        uint256 idx = 0;
        uint256 count = max_per_block * 64;

        for (; idx < count; idx++) {
            addRequest(nextAddress(idx), makeSweepThreshold(idx), 1);
        }
        assertStorage(count_slot, count, "unexpected request count");
        checkSweepThresholds(0, max_per_block);

        uint256 read = max_per_block;
        uint256 excess = count - target_per_block;

        for (uint256 i = 0; i < count; i++) {
            assertExcess(excess);

            uint256 fee = computeFee(excess);
            addFailedRequest(address(uint160(idx)), makeSweepThreshold(idx), fee - 1);
            addRequest(nextAddress(idx), makeSweepThreshold(idx), fee);

            uint256 expected = min(idx - read + 1, max_per_block);
            checkSweepThresholds(read, expected);

            if (excess != 0) {
                excess--;
            }
            read += expected;
            idx++;
        }
    }

    // testInhibitorReset verifies that the first system call resets the excess
    // inhibitor and that other excess values are updated normally.
    function testInhibitorReset() public {
        vm.store(addr, bytes32(0), bytes32(inhibitor));
        vm.prank(sysaddr);
        (bool ret, bytes memory data) = addr.call("");
        assertEq(ret, true);
        assertEq(data.length, 0);
        assertStorage(excess_slot, 0, "expected excess requests to be reset");

        vm.store(addr, bytes32(0), bytes32(inhibitor));
        addFailedRequest(address(uint160(0)), makeSweepThreshold(0), inhibitor);

        vm.store(addr, bytes32(0), bytes32(inhibitor - 1));
        vm.prank(sysaddr);
        (ret, data) = addr.call("");
        assertEq(ret, true);
        assertEq(data.length, 0);
        assertStorage(excess_slot, inhibitor - target_per_block - 1, "didn't expect excess to be reset");
    }

    // testSetInhibitorViaSystemCall verifies that a system call with input sets the
    // inhibitor to prevent further additions. The requests are still dequeued as
    // usual, i.e. up to max_per_block per call, so repeated calls with input drain
    // the queue and eventually reset it, all while keeping the queue disabled.
    function testSetInhibitorViaSystemCall() public {
        uint256 requestCount = max_per_block + 4;
        for (uint256 i = 0; i < requestCount; i++) {
            addRequest(nextAddress(i), makeSweepThreshold(i), 2);
        }

        // Disable the queue with a system call that carries input data. Only
        // max_per_block requests are dequeued, the rest remain in the queue.
        vm.prank(sysaddr);
        (bool ret, bytes memory data) = addr.call(hex"01");
        assertEq(ret, true);
        checkRequestData(data, 0, max_per_block);
        assertStorage(excess_slot, inhibitor, "expected inhibitor in excess storage slot");
        assertStorage(queue_head_slot, max_per_block, "unexpected queue head");
        assertStorage(queue_tail_slot, requestCount, "unexpected queue tail");

        // Check that requesting the current fee fails.
        (ret,) = addr.staticcall("");
        assertEq(ret, false, "expected fee getter to fail");

        // Check that adding a request fails.
        addFailedRequest(nextAddress(requestCount), makeSweepThreshold(requestCount), 2);

        // A subsequent system call with input dequeues the remaining requests and
        // resets the queue pointers, while keeping the queue disabled.
        vm.prank(sysaddr);
        (ret, data) = addr.call(hex"01");
        assertEq(ret, true);
        checkRequestData(data, max_per_block, requestCount - max_per_block);
        assertStorage(excess_slot, inhibitor, "expected inhibitor to remain in excess storage slot");
        assertStorage(queue_head_slot, 0, "expected queue head reset");
        assertStorage(queue_tail_slot, 0, "expected queue tail reset");

        // Further system calls with input return no data and keep the queue disabled.
        vm.prank(sysaddr);
        (ret, data) = addr.call(hex"01");
        assertEq(ret, true);
        assertEq(data.length, 0, "expected no requests from an empty queue");
        assertStorage(excess_slot, inhibitor, "expected inhibitor to remain in excess storage slot");

        // Check that adding a request still fails.
        addFailedRequest(nextAddress(requestCount), makeSweepThreshold(requestCount), 2);

        // Now re-enable the queue through a system call with no input.
        vm.prank(sysaddr);
        (ret, data) = addr.call("");
        assertEq(ret, true);
        assertEq(data.length, 0, "expected no requests from an empty queue");
        assertStorage(excess_slot, 0, "expected zero excess requests after re-enabling queue");

        // Check that adding a request succeeds again.
        addRequest(nextAddress(requestCount + 1), makeSweepThreshold(requestCount + 1), 2);
    }

    // testQueueDisableFeeReset verifies that re-enabling the queue resets the fee to 1.
    function testQueueDisableFeeReset() public {
        uint256 requestCount = max_per_block * 4;
        for (uint256 i = 0; i < requestCount; i++) {
            uint256 fee = getCurrentFee();
            addRequest(nextAddress(i), makeSweepThreshold(i), fee);
        }
        assertStorage(count_slot, requestCount, "unexpected request count");

        // Disable the queue with a system call that carries input data.
        vm.prank(sysaddr);
        (bool ret, bytes memory data) = addr.call(hex"01");
        assertEq(ret, true);
        assertEq(data.length, max_per_block * 76, "expected max_per_block requests to be dequeued");
        assertStorage(excess_slot, inhibitor, "expected inhibitor in excess storage slot");

        // Now re-enable the queue through a system call with no input.
        vm.prank(sysaddr);
        (ret, data) = addr.call("");
        assertEq(ret, true);
        assertEq(data.length, max_per_block * 76, "expected max_per_block requests to be dequeued");
        assertStorage(excess_slot, 0, "expected zero excess requests after re-enabling queue");

        // Check that adding a request succeeds again with fee 1.
        addRequest(nextAddress(999), makeSweepThreshold(999), 1);
    }

    // addRequest submits a request and verifies its queue storage representation.
    function addRequest(address from, bytes memory req, uint256 value) internal {
        uint256 requests = load(count_slot);
        uint256 tail = load(queue_tail_slot);

        vm.deal(from, value);
        vm.prank(from);
        (bool ret,) = addr.call{value: value}(req);
        assertEq(ret, true, "expected call to succeed");

        assertStorage(count_slot, requests + 1, "unexpected request count");
        assertStorage(queue_tail_slot, tail + 1, "unexpected tail slot");

        uint256 idx = queue_storage_offset + tail * 3;
        assertStorage(idx, uint256(uint160(from)), "address not written to queue");
        assertStorage(idx + 1, toFixed(req, 0, 32), "pubkey[0:32] not written to queue");
        assertStorage(idx + 2, toFixed(req, 32, 56), "pubkey[32:48] and threshold not written to queue");
    }

    // checkSweepThresholds simulates a system call and verifies the returned requests.
    function checkSweepThresholds(uint256 startIndex, uint256 count) internal {
        bytes memory requests = getRequests();
        checkRequestData(requests, startIndex, count);
    }

    // checkRequestData verifies the given dequeued request data against the
    // requests generated from startIndex onwards.
    function checkRequestData(bytes memory requests, uint256 startIndex, uint256 count) internal {
        assertEq(requests.length, count * 76);

        for (uint256 i = 0; i < count; i++) {
            uint256 offset = i * 76;
            uint256 requestIndex = startIndex + i;
            bytes memory request = makeSweepThreshold(requestIndex);

            assertEq(
                address(uint160(toFixed(requests, offset, offset + 20) >> 96)),
                address(nextAddress(requestIndex)),
                "unexpected request address returned"
            );
            assertEq(
                bytes32(toFixed(requests, offset + 20, offset + 52)),
                bytes32(toFixed(request, 0, 32)),
                "unexpected pubkey[0:32] returned"
            );
            assertEq(
                bytes16(uint128(toFixed(requests, offset + 52, offset + 68) >> 128)),
                bytes16(uint128(toFixed(request, 32, 48) >> 128)),
                "unexpected pubkey[32:48] returned"
            );

            uint256 thresholdRecovered = toFixed(requests, offset + 68, offset + 68 + 8);
            uint256 thresholdSent = toFixed(request, 48, 48 + 8) >> 192;
            assertEq(endianReverse(thresholdRecovered), thresholdSent, "unexpected threshold returned");
        }
    }

    // Returns pseudo-random address based on X.
    function nextAddress(uint256 x) internal returns (address out) {
        bytes memory data = randomBytesN(address_seed, 20);
        assembly {
            out := shr(96, mload(add(data, 32)))
        }

        vm.label(out, string.concat("ADDR_", vm.toString(x)));
    }

    // makeSweepThreshold constructs a request with a public key based on X.
    function makeSweepThreshold(uint256 x) internal pure returns (bytes memory) {
        bytes memory pubkey = randomBytesN(pubkey_seed + x, 48);
        bytes memory threshold = randomBytesN(threshold_seed + x, 8);
        bytes memory out = bytes.concat(pubkey, threshold);
        assertEq(out.length, 56, "built sweep_threshold payload with invalid length");
        return out;
    }

    // getCurrentFee returns the current fee computed by the system contract.
    function getCurrentFee() internal view returns (uint256) {
        (bool ok, bytes memory data) = addr.staticcall("");
        assert(ok);
        return uint256(bytes32(data));
    }

    function minstd(uint256 state) internal pure returns (uint256) {
        require(state > 0 && state < 2147483647, "invalid seed");
        return mulmod(state, 48271, 2147483647);
    }

    function randomBytesN(uint256 seed, uint256 len) internal pure returns (bytes memory out) {
        out = new bytes(len);

        for (uint256 i = 0; i < len; i++) {
            seed = minstd(seed);
            out[i] = bytes1(uint8(seed));
        }
    }

    function endianReverse(uint256 v) internal pure returns (uint256 r) {
        assembly {
            for {
                let i := 0
            } lt(i, 32) {
                i := add(i, 1)
            } {
                r := or(shl(8, r), and(v, 0xff))
                v := shr(8, v)
            }
        }
    }
}
