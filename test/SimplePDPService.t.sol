// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SimplePDPService} from "../src/SimplePDPService.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {Cids} from "../src/Cids.sol";

contract SimplePDPServiceTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;
    bytes empty = new bytes(0);
    uint256 public dataSetId;
    uint256 public leafCount;
    uint256 public seed;

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData =
            abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
        dataSetId = 1;
        leafCount = 100;
        seed = 12345;
    }

    function testInitialState() public view {
        assertEq(pdpService.pdpVerifierAddress(), pdpVerifierAddress, "PDP verifier address should be set correctly");
    }

    function testOnlyPDPVerifierCanAddRecord() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Caller is not the PDP verifier");
        pdpService.dataSetCreated(dataSetId, address(this), empty);
    }

    function testGetMaxProvingPeriod() public view {
        uint64 maxPeriod = pdpService.getMaxProvingPeriod();
        assertEq(maxPeriod, 2880, "Max proving period should be 2880");
    }

    function testGetChallengesPerProof() public view {
        uint64 challenges = pdpService.getChallengesPerProof();
        assertEq(challenges, 5, "Challenges per proof should be 5");
    }

    function testInitialProvingPeriodHappyPath() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        uint256 challengeEpoch = pdpService.initChallengeWindowStart();

        pdpService.nextProvingPeriod(dataSetId, challengeEpoch, leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(dataSetId),
            block.number + pdpService.getMaxProvingPeriod(),
            "Deadline should be set to current block + max period"
        );
        assertFalse(pdpService.provenThisPeriod(dataSetId));
    }

    function testInitialProvingPeriodInvalidChallengeEpoch() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        uint256 firstDeadline = block.number + pdpService.getMaxProvingPeriod();

        // Test too early
        uint256 tooEarly = firstDeadline - pdpService.challengeWindow() - 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(dataSetId, tooEarly, leafCount, empty);

        // Test too late
        uint256 tooLate = firstDeadline + 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(dataSetId, tooLate, leafCount, empty);
    }

    function testProveBeforeInitialization() public {
        // Create a simple mock proof
        vm.expectRevert("Proving not yet started");
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);
    }

    function testInactivateDataSetHappyPath() public {
        // Setup initial state
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Prove possession in first period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);

        // Inactivate the data set
        pdpService.nextProvingPeriod(dataSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(dataSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
        assertEq(pdpService.provenThisPeriod(dataSetId), false, "Proven this period should now be false");
    }
}

contract SimplePDPServiceFaultsTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;
    uint256 public dataSetId;
    uint256 public leafCount;
    uint256 public seed;
    uint256 public challengeCount;
    bytes empty = new bytes(0);

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData =
            abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
        dataSetId = 1;
        leafCount = 100;
        seed = 12345;
        challengeCount = 5;
    }

    function testPossessionProvenOnTime() public {
        // Set up the proving deadline
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(dataSetId));

        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodCalledLastMinuteOK() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);

        // wait until almost the end of proving period 2
        // this should all work fine
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);
    }

    function testFirstEpochLateToProve() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodTwiceFails() public {
        // Set up the proving deadline
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);
        uint256 deadline1 = pdpService.provingDeadlines(dataSetId);
        assertTrue(pdpService.provenThisPeriod(dataSetId));

        assertEq(
            pdpService.provingDeadlines(dataSetId),
            deadline1,
            "Proving deadline should not change until nextProvingPeriod."
        );
        uint256 challengeEpoch = pdpService.nextChallengeWindowStart(dataSetId);
        pdpService.nextProvingPeriod(dataSetId, challengeEpoch, leafCount, empty);
        assertEq(
            pdpService.provingDeadlines(dataSetId),
            deadline1 + pdpService.getMaxProvingPeriod(),
            "Proving deadline should be updated"
        );
        assertFalse(pdpService.provenThisPeriod(dataSetId));

        vm.expectRevert("One call to nextProvingPeriod allowed per proving period");
        pdpService.nextProvingPeriod(dataSetId, challengeEpoch, leafCount, empty);
    }

    function testFaultWithinOpenPeriod() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move to open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);

        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(dataSetId, 1, pdpService.provingDeadlines(dataSetId));
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
    }

    function testFaultAfterPeriodOver() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move past proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);

        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(dataSetId, 1, pdpService.provingDeadlines(dataSetId));
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
    }

    function testNextProvingPeriodWithoutProof() public {
        // Set up the proving deadline without marking as proven
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Move to the next period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        // Expect a fault event
        vm.expectEmit();
        emit SimplePDPService.FaultRecord(dataSetId, 1, pdpService.provingDeadlines(dataSetId));
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
        assertFalse(pdpService.provenThisPeriod(dataSetId));
    }

    function testInvalidChallengeCount() public {
        uint256 invalidChallengeCount = 4; // Less than required

        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.expectRevert("Invalid challenge count < 5");
        pdpService.possessionProven(dataSetId, leafCount, seed, invalidChallengeCount);
    }

    function testMultiplePeriodsLate() public {
        // Set up the proving deadline
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);
        // unable to prove possession
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);

        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(dataSetId, 3, pdpService.provingDeadlines(dataSetId));
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
    }

    function testMultiplePeriodsLateWithInitialProof() public {
        // Set up the proving deadline
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);

        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Move to first open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());

        // Submit valid proof in first period
        pdpService.possessionProven(dataSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(dataSetId));

        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);

        // Should emit fault record for 2 periods (current period not counted since not yet expired)
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(dataSetId, 2, pdpService.provingDeadlines(dataSetId));
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
    }

    function testCanOnlyProveOncePerPeriod() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // We're in the previous deadline so we fail to prove until we roll forward into challenge window
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow() - 1);
        // We're one before the challenge window so we should still fail
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);
        // now we succeed
        vm.roll(block.number + 1);
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);
        vm.expectRevert("Only one proof of possession allowed per proving period. Open a new proving period.");
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);
    }

    function testCantProveBeforePeriodIsOpen() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);
    }

    function testMissChallengeWindow() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);
        // Too early
        uint256 tooEarly = pdpService.nextChallengeWindowStart(dataSetId) - 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(dataSetId, tooEarly, leafCount, empty);
        // Too late
        uint256 tooLate = pdpService.nextChallengeWindowStart(dataSetId) + pdpService.challengeWindow() + 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(dataSetId, tooLate, leafCount, empty);

        // Works right on the deadline
        pdpService.nextProvingPeriod(
            dataSetId, pdpService.nextChallengeWindowStart(dataSetId) + pdpService.challengeWindow(), leafCount, empty
        );
    }

    function testMissChallengeWindowAfterFaults() public {
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Skip 2 proving periods
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 - 100);

        // Too early
        uint256 tooEarly = pdpService.nextChallengeWindowStart(dataSetId) - 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(dataSetId, tooEarly, leafCount, empty);

        // Too late
        uint256 tooLate = pdpService.nextChallengeWindowStart(dataSetId) + pdpService.challengeWindow() + 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(dataSetId, tooLate, leafCount, empty);

        // Should emit fault record for 2 periods
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(dataSetId, 2, pdpService.provingDeadlines(dataSetId));
        // Works right on the deadline
        pdpService.nextProvingPeriod(
            dataSetId, pdpService.nextChallengeWindowStart(dataSetId) + pdpService.challengeWindow(), leafCount, empty
        );
    }

    function testInactivateWithCurrentPeriodFault() public {
        // Setup initial state
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move to end of period without proving
        vm.roll(block.number + pdpService.getMaxProvingPeriod());

        // Expect fault event for the unproven period
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(dataSetId, 1, pdpService.provingDeadlines(dataSetId));

        pdpService.nextProvingPeriod(dataSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(dataSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
    }

    function testInactivateWithMultiplePeriodFaults() public {
        // Setup initial state
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Skip 3 proving periods without proving
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);

        // Expect fault event for all missed periods
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(dataSetId, 3, pdpService.provingDeadlines(dataSetId));

        pdpService.nextProvingPeriod(dataSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(dataSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
    }

    function testGetPDPConfig() public view {
        (uint64 maxProvingPeriod, uint256 challengeWindow, uint256 challengesPerProof, uint256 initChallengeWindowStart)
        = pdpService.getPDPConfig();

        assertEq(maxProvingPeriod, 2880, "Max proving period should be 2880");
        assertEq(challengeWindow, 60, "Challenge window should be 60");
        assertEq(challengesPerProof, 5, "Challenges per proof should be 5");
        assertEq(
            initChallengeWindowStart,
            block.number + 2880 - 60,
            "Init challenge window start should be calculated correctly"
        );
    }

    function testNextPDPChallengeWindowStart() public {
        // Setup initial state
        pdpService.piecesAdded(dataSetId, 0, new Cids.Cid[](0), empty);
        pdpService.nextProvingPeriod(dataSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Test that nextPDPChallengeWindowStart returns the same as nextChallengeWindowStart
        uint256 expected = pdpService.nextChallengeWindowStart(dataSetId);
        uint256 actual = pdpService.nextPDPChallengeWindowStart(dataSetId);
        assertEq(actual, expected, "nextPDPChallengeWindowStart should match nextChallengeWindowStart");

        // Move to challenge window and prove
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(dataSetId, leafCount, seed, 5);

        // Open next period
        pdpService.nextProvingPeriod(dataSetId, pdpService.nextChallengeWindowStart(dataSetId), leafCount, empty);

        // Test again in new period
        expected = pdpService.nextChallengeWindowStart(dataSetId);
        actual = pdpService.nextPDPChallengeWindowStart(dataSetId);
        assertEq(actual, expected, "nextPDPChallengeWindowStart should match nextChallengeWindowStart in new period");
    }

    function testNextPDPChallengeWindowStartNotInitialized() public {
        // Test that it reverts when proving period not initialized
        vm.expectRevert("Proving period not yet initialized");
        pdpService.nextPDPChallengeWindowStart(dataSetId);
    }
}
