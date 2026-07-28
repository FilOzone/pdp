// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";
import {Vm} from "forge-std/Vm.sol";
import {Cids} from "../src/Cids.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {PDPFees} from "../src/Fees.sol";

contract PDPVerifierStorageTest is MockFVMTest {
    struct StorageMetrics {
        uint256 reads;
        uint256 writes;
        uint256 kamtObjectsTouched;
        uint256 kamtObjectsModified;
        uint256 newOccupiedSlots;
    }

    PDPVerifier private verifier;

    function setUp() public override {
        super.setUp();
        PDPVerifier implementation = new PDPVerifier(1, 2);
        bytes memory initializeData = abi.encodeWithSelector(PDPVerifier.initialize.selector);
        verifier = PDPVerifier(address(new MyERC1967Proxy(address(implementation), initializeData)));
    }

    function testAddPiecesStorageMetrics() public {
        uint256[4] memory batchSizes = [uint256(1), 4, 16, 32];
        // Measurements include fixed dataset/sum-tree activity; compact records add two slots each.
        uint256[4] memory expectedReads = [uint256(12), 25, 85, 165];
        uint256[4] memory expectedWrites = [uint256(4), 13, 49, 97];
        uint256[4] memory expectedTouchedObjects = [uint256(7), 7, 8, 9];
        uint256[4] memory expectedModifiedObjects = [uint256(3), 3, 4, 5];

        for (uint256 i; i < batchSizes.length; ++i) {
            StorageMetrics memory metrics = _measureAddPieces(batchSizes[i]);

            emit log_named_uint("batch size", batchSizes[i]);
            emit log_named_uint("storage reads", metrics.reads);
            emit log_named_uint("storage writes", metrics.writes);
            emit log_named_uint("KAMT objects touched", metrics.kamtObjectsTouched);
            emit log_named_uint("KAMT objects modified", metrics.kamtObjectsModified);
            emit log_named_uint("new occupied slots", metrics.newOccupiedSlots);

            assertEq(metrics.reads, expectedReads[i], "unexpected storage read count");
            assertEq(metrics.writes, expectedWrites[i], "unexpected storage write count");
            assertEq(metrics.kamtObjectsTouched, expectedTouchedObjects[i], "unexpected KAMT object access count");
            assertEq(metrics.kamtObjectsModified, expectedModifiedObjects[i], "unexpected KAMT object write count");
            assertEq(metrics.newOccupiedSlots, 2 * batchSizes[i], "unexpected storage growth");
        }
    }

    function _measureAddPieces(uint256 batchSize) private returns (StorageMetrics memory metrics) {
        uint256 setId = verifier.createDataSet{value: PDPFees.cleanupDeposit()}(address(0), bytes(""));

        // Seed the data set before recording so the array header and shared counters already occupy storage.
        Cids.Cid[] memory seed = new Cids.Cid[](1);
        seed[0] = Cids.CommPv2FromDigest(0, 5, bytes32(uint256(1)));
        verifier.addPieces(setId, address(0), seed, bytes(""));

        Cids.Cid[] memory pieces = new Cids.Cid[](batchSize);
        for (uint256 i; i < pieces.length; ++i) {
            pieces[i] = Cids.CommPv2FromDigest(0, uint8(6 + i), bytes32(i + 2));
        }

        vm.startStateDiffRecording();
        verifier.addPieces(setId, address(0), pieces, bytes(""));
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        return _storageMetrics(accesses, address(verifier));
    }

    function _storageMetrics(Vm.AccountAccess[] memory accesses, address storageAccount)
        private
        pure
        returns (StorageMetrics memory metrics)
    {
        uint256 capacity;
        for (uint256 i; i < accesses.length; ++i) {
            capacity += accesses[i].storageAccesses.length;
        }

        bytes32[] memory touchedObjects = new bytes32[](capacity);
        bytes32[] memory modifiedObjects = new bytes32[](capacity);
        bytes32[] memory writtenSlots = new bytes32[](capacity);
        bytes32[] memory initialValues = new bytes32[](capacity);
        bytes32[] memory finalValues = new bytes32[](capacity);
        uint256 touchedObjectCount;
        uint256 modifiedObjectCount;
        uint256 writtenSlotCount;

        for (uint256 i; i < accesses.length; ++i) {
            if (accesses[i].reverted) continue;
            Vm.StorageAccess[] memory storageAccesses = accesses[i].storageAccesses;
            for (uint256 j; j < storageAccesses.length; ++j) {
                Vm.StorageAccess memory access = storageAccesses[j];
                if (access.account != storageAccount || access.reverted) continue;

                bytes32 objectId = bytes32(uint256(access.slot) >> 5);
                touchedObjectCount = _addUnique(touchedObjects, touchedObjectCount, objectId);

                if (access.isWrite) {
                    ++metrics.writes;
                    modifiedObjectCount = _addUnique(modifiedObjects, modifiedObjectCount, objectId);

                    (bool found, uint256 slotIndex) = _find(writtenSlots, writtenSlotCount, access.slot);
                    if (!found) {
                        slotIndex = writtenSlotCount++;
                        writtenSlots[slotIndex] = access.slot;
                        initialValues[slotIndex] = access.previousValue;
                    }
                    finalValues[slotIndex] = access.newValue;
                } else {
                    ++metrics.reads;
                }
            }
        }

        metrics.kamtObjectsTouched = touchedObjectCount;
        metrics.kamtObjectsModified = modifiedObjectCount;
        for (uint256 i; i < writtenSlotCount; ++i) {
            if (initialValues[i] == bytes32(0) && finalValues[i] != bytes32(0)) {
                ++metrics.newOccupiedSlots;
            }
        }
    }

    function _addUnique(bytes32[] memory values, uint256 length, bytes32 value) private pure returns (uint256) {
        (bool found,) = _find(values, length, value);
        if (found) return length;
        values[length] = value;
        return length + 1;
    }

    function _find(bytes32[] memory values, uint256 length, bytes32 value)
        private
        pure
        returns (bool found, uint256 index)
    {
        for (uint256 i; i < length; ++i) {
            if (values[i] == value) return (true, i);
        }
        return (false, length);
    }
}
