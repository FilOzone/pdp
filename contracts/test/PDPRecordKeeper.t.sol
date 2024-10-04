// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPRecordKeeperApplication, PDPApplication} from "../src/PDPRecordKeeperApplication.sol";

contract PDPRecordKeeperTest is Test {
    PDPRecordKeeperApplication public recordKeeper;
    address public pdpServiceAddress;

    function setUp() public {
        pdpServiceAddress = address(this);
        recordKeeper = new PDPRecordKeeperApplication(pdpServiceAddress);
    }

    function testInitialState() public view {
        assertEq(recordKeeper.pdpServiceAddress(), pdpServiceAddress, "PDP service address should be set correctly");
    }

    function testAddRecord() public {
        uint256 proofSetId = 1;
        uint64 epoch = 100;
        PDPApplication.OperationType operationType = PDPApplication.OperationType.CREATE;
        bytes memory extraData = abi.encode("test data");

        recordKeeper.notify(proofSetId, epoch, operationType, extraData);

        assertEq(recordKeeper.getEventCount(proofSetId), 1, "Event count should be 1 after adding a record");

        PDPRecordKeeperApplication.EventRecord memory eventRecord = recordKeeper.getEvent(proofSetId, 0);

        assertEq(eventRecord.epoch, epoch, "Recorded epoch should match");
        assertEq(uint(eventRecord.operationType), uint(operationType), "Recorded operation type should match");
        assertEq(eventRecord.extraData, extraData, "Recorded extra data should match");
    }

    function testListEvents() public {
        uint256 proofSetId = 1;
        uint64 epoch1 = 100;
        uint64 epoch2 = 200;
        PDPApplication.OperationType operationType1 = PDPApplication.OperationType.CREATE;
        PDPApplication.OperationType operationType2 = PDPApplication.OperationType.ADD;
        bytes memory extraData1 = abi.encode("test data 1");
        bytes memory extraData2 = abi.encode("test data 2");

        recordKeeper.notify(proofSetId, epoch1, operationType1, extraData1);
        recordKeeper.notify(proofSetId, epoch2, operationType2, extraData2);

        PDPRecordKeeperApplication.EventRecord[] memory events = recordKeeper.listEvents(proofSetId);

        assertEq(events.length, 2, "Should have 2 events");
        assertEq(events[0].epoch, epoch1, "First event epoch should match");
        assertEq(uint(events[0].operationType), uint(operationType1), "First event operation type should match");
        assertEq(events[0].extraData, extraData1, "First event extra data should match");
        assertEq(events[1].epoch, epoch2, "Second event epoch should match");
        assertEq(uint(events[1].operationType), uint(operationType2), "Second event operation type should match");
        assertEq(events[1].extraData, extraData2, "Second event extra data should match");
    }

    function testOnlyPDPServiceCanAddRecord() public {
        uint256 proofSetId = 1;
        uint64 epoch = 100;
        PDPApplication.OperationType operationType = PDPApplication.OperationType.CREATE;
        bytes memory extraData = abi.encode("test data");

        vm.prank(address(0xdead));
        vm.expectRevert("Caller is not the PDP service");
        recordKeeper.notify(proofSetId, epoch, operationType, extraData);
    }

    function testGetEventOutOfBounds() public {
        uint256 proofSetId = 1;
        vm.expectRevert("Event index out of bounds");
        recordKeeper.getEvent(proofSetId, 0);
    }
}