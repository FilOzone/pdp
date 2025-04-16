// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPListener, PDPVerifier} from "../src/PDPVerifier.sol";
import {SimplePDPService, PDPRecordKeeper} from "../src/SimplePDPService.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {Cids} from "../src/Cids.sol";


contract SimplePDPServiceTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;
    bytes empty = new bytes(0);
    uint256 public proofSetId;
    uint256 public leafCount;
    uint256 public seed;

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
        proofSetId = 1;
        leafCount = 100;
        seed = 12345;

    }

    function testInitialState() public view {
        assertEq(pdpService.pdpVerifierAddress(), pdpVerifierAddress, "PDP verifier address should be set correctly");
    }


    function testOnlyPDPVerifierCanAddRecord() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Caller is not the PDP verifier");
        pdpService.proofSetCreated(proofSetId, address(this), empty);
    }

    function testGetMaxProvingPeriod() public view {
        uint64 maxPeriod = pdpService.getMaxProvingPeriod();
        assertEq(maxPeriod, 2880, "Max proving period should be 2880");
    }

    function testGetChallengesPerProof() public view{
        uint64 challenges = pdpService.getChallengesPerProof();
        assertEq(challenges, 5, "Challenges per proof should be 5");
    }

    function testInitialProvingPeriodHappyPath() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        uint256 challengeEpoch = pdpService.initChallengeWindowStart();

        pdpService.nextProvingPeriod(proofSetId, challengeEpoch, leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            block.number + pdpService.getMaxProvingPeriod(),
            "Deadline should be set to current block + max period"
        );
        assertFalse(pdpService.provenThisPeriod(proofSetId));
    }

    function testInitialProvingPeriodInvalidChallengeEpoch() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        uint256 firstDeadline = block.number + pdpService.getMaxProvingPeriod();

        // Test too early
        uint256 tooEarly = firstDeadline - pdpService.challengeWindow() - 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooEarly, leafCount, empty);

        // Test too late
        uint256 tooLate = firstDeadline + 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooLate, leafCount, empty);
    }

    function testProveBeforeInitialization() public {
        
        // Create a simple mock proof
        vm.expectRevert("Proving not yet started");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
    }

    function testInactivateProofSetHappyPath() public {
        // Setup initial state
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Prove possession in first period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);

        // Inactivate the proof set
        pdpService.nextProvingPeriod(proofSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
        assertEq(
            pdpService.provenThisPeriod(proofSetId),
            false,
            "Proven this period should now be false"
        );
    }
}

contract SimplePDPServiceFaultsTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;
    uint256 public proofSetId;
    uint256 public leafCount;
    uint256 public seed;
    uint256 public challengeCount;
    bytes empty = new bytes(0);

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
        proofSetId = 1;
        leafCount = 100;
        seed = 12345;
        challengeCount = 5;
    }

    function testPossessionProvenOnTime() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodCalledLastMinuteOK() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);

        // wait until almost the end of proving period 2
        // this should all work fine
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testFirstEpochLateToProve() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodTwiceFails() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        uint256 deadline1 = pdpService.provingDeadlines(proofSetId);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        assertEq(pdpService.provingDeadlines(proofSetId), deadline1, "Proving deadline should not change until nextProvingPeriod.");
        uint256 challengeEpoch = pdpService.nextChallengeWindowStart(proofSetId);
        pdpService.nextProvingPeriod(proofSetId, challengeEpoch, leafCount, empty);
        assertEq(pdpService.provingDeadlines(proofSetId), deadline1 + pdpService.getMaxProvingPeriod(), "Proving deadline should be updated");
        assertFalse(pdpService.provenThisPeriod(proofSetId));

        vm.expectRevert("One call to nextProvingPeriod allowed per proving period");
        pdpService.nextProvingPeriod(proofSetId, challengeEpoch, leafCount, empty);
    }

    function testFaultWithinOpenPeriod() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move to open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);

        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testFaultAfterPeriodOver() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move past proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);

        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testNextProvingPeriodWithoutProof() public {
        // Set up the proving deadline without marking as proven
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Move to the next period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        // Expect a fault event
        vm.expectEmit();
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        assertFalse(pdpService.provenThisPeriod(proofSetId));
    }

    function testInvalidChallengeCount() public {
        uint256 invalidChallengeCount = 4; // Less than required

        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.expectRevert("Invalid challenge count < 5");
        pdpService.possessionProven(proofSetId, leafCount, seed, invalidChallengeCount);
    }

    function testMultiplePeriodsLate() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);
        // unable to prove possession
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);

        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 3, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testMultiplePeriodsLateWithInitialProof() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);

        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Move to first open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());

        // Submit valid proof in first period
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);

        // Should emit fault record for 2 periods (current period not counted since not yet expired)
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 2, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testCanOnlyProveOncePerPeriod() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // We're in the previous deadline so we fail to prove until we roll forward into challenge window
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow() -1);
        // We're one before the challenge window so we should still fail
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        // now we succeed
        vm.roll(block.number + 1);
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        vm.expectRevert("Only one proof of possession allowed per proving period. Open a new proving period.");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
    }

    function testCantProveBeforePeriodIsOpen() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
    }

    function testMissChallengeWindow() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);
        // Too early
        uint256 tooEarly = pdpService.nextChallengeWindowStart(proofSetId)-1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooEarly, leafCount, empty);
        // Too late
        uint256 tooLate = pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow()+1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooLate, leafCount, empty);

        // Works right on the deadline
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow(), leafCount, empty);
    }

    function testMissChallengeWindowAfterFaults() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Skip 2 proving periods
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 - 100);

        // Too early
        uint256 tooEarly = pdpService.nextChallengeWindowStart(proofSetId)-1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooEarly, leafCount, empty);

        // Too late
        uint256 tooLate = pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow()+1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooLate, leafCount, empty);

        // Should emit fault record for 2 periods
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 2, pdpService.provingDeadlines(proofSetId));
        // Works right on the deadline
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow(), leafCount, empty);
    }

    function testInactivateWithCurrentPeriodFault() public {
        // Setup initial state
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move to end of period without proving
        vm.roll(block.number + pdpService.getMaxProvingPeriod());

        // Expect fault event for the unproven period
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));

        pdpService.nextProvingPeriod(proofSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
    }

    function testInactivateWithMultiplePeriodFaults() public {
        // Setup initial state
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Skip 3 proving periods without proving
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);

        // Expect fault event for all missed periods
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 3, pdpService.provingDeadlines(proofSetId));

        pdpService.nextProvingPeriod(proofSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
    }
    
    // Tests for calculateFaultsBetweenEpochs function
    
    function testCalculateFaultsBasicCase() public {
        // Setup initial state - first proving period
        uint256 startBlock = block.number;
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        
        // Move to challenge window and prove possession
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        
        // Start next proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Don't prove for this period (this will be a fault)
        
        // Start third proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() * 2);
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Move to challenge window and prove possession
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() * 2 + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        
        // Start fourth proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() * 3);
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Calculate faults for the whole range
        (uint256 faultCount, uint256 lastConsideredEpoch) = pdpService.calculateFaultsBetweenEpochs(
            proofSetId, 
            startBlock, 
            startBlock + pdpService.getMaxProvingPeriod() * 4
        );
        
        // Second period wasn't proven, so we should have getMaxProvingPeriod() epochs with faults
        assertEq(faultCount, pdpService.getMaxProvingPeriod(), "Should count exactly one period of faults");
        assertEq(lastConsideredEpoch, startBlock + pdpService.getMaxProvingPeriod() * 3, "Last considered epoch should be end of third period");
    }
    
    function testCalculateFaultsMultiplePeriods() public {
        // Setup initial state
        uint256 startBlock = block.number;
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        
        // First period - don't prove possession (fault)
        
        // Start second proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Second period - don't prove possession (fault)
        
        // Start third proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() * 2);
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Third period - prove possession
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() * 2 + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        
        // Start fourth proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() * 3);
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Calculate faults for the whole range
        (uint256 faultCount, uint256 lastConsideredEpoch) = pdpService.calculateFaultsBetweenEpochs(
            proofSetId, 
            startBlock, 
            startBlock + pdpService.getMaxProvingPeriod() * 4
        );
        
        // First two periods weren't proven, so we should have 2*getMaxProvingPeriod() epochs with faults
        assertEq(faultCount, pdpService.getMaxProvingPeriod() * 2, "Should count exactly two periods of faults");
        assertEq(lastConsideredEpoch, startBlock + pdpService.getMaxProvingPeriod() * 3, "Last considered epoch should be end of third period");
    }
    
    function testCalculateFaultsPartialRange() public {
        // Setup initial state
        uint256 startBlock = block.number;
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        
        // First period - don't prove possession (fault)
        
        // Start second proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Second period - don't prove possession (fault)
        
        // Start third proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() * 2);
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Calculate faults for a partial range - middle of first period to middle of second period
        uint256 rangeStart = startBlock + pdpService.getMaxProvingPeriod() / 2; // Middle of first period
        uint256 rangeEnd = startBlock + pdpService.getMaxProvingPeriod() + pdpService.getMaxProvingPeriod() / 2; // Middle of second period
        
        (uint256 faultCount, uint256 lastConsideredEpoch) = pdpService.calculateFaultsBetweenEpochs(
            proofSetId, 
            rangeStart, 
            rangeEnd
        );
        
        // Expected faults: half of period 1 + half of period 2 = getMaxProvingPeriod()
        uint256 expectedFaults = pdpService.getMaxProvingPeriod();
        assertEq(faultCount, expectedFaults, "Should count exactly one period worth of faults");
        
        // For our range that ends in the middle of the second period, lastConsideredEpoch should be rangeEnd
        assertEq(lastConsideredEpoch, rangeEnd, "Last considered epoch should match rangeEnd");
    }
    
    function testCalculateFaultsNotInitializedProofSet() public view {
        // Don't initialize the proof set - no calls to nextProvingPeriod
        uint256 startBlock = block.number;
        
        // Calculate faults - should return 0 since proof set wasn't initialized for proving
        (uint256 faultCount, uint256 lastConsideredEpoch) = pdpService.calculateFaultsBetweenEpochs(
            proofSetId, 
            startBlock, 
            startBlock + 1000
        );
        
        assertEq(faultCount, 0, "Should count zero faults for uninitialized proof set");
        assertEq(lastConsideredEpoch, startBlock, "Last considered epoch should be startBlock");
    }
    
    function testCalculateFaultsFutureRange() public {
        // Setup initial state with several periods
        uint256 startBlock = block.number;
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        
        // First period - prove possession
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        
        // Start second proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Calculate faults for a range in the future (beyond recorded periods)
        uint256 futureStart = startBlock + pdpService.getMaxProvingPeriod() * 5;
        uint256 futureEnd = startBlock + pdpService.getMaxProvingPeriod() * 6;
        
        (uint256 faultCount, uint256 lastConsideredEpoch) = pdpService.calculateFaultsBetweenEpochs(
            proofSetId, 
            futureStart, 
            futureEnd
        );
        
        // Should return 0 faults since we can't count faults for future/unrecorded periods
        assertEq(faultCount, 0, "Should count zero faults for future range");
        assertEq(lastConsideredEpoch, startBlock + pdpService.getMaxProvingPeriod(), "Last considered epoch should be end of last recorded period");
    }
    
    function testCalculateFaultsBeforeProvingStarted() public {
        // Start at a high block number so we can query before it
        vm.roll(10000);
        uint256 startBlock = block.number;
        
        // Initialize the proof set
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        
        // Don't prove possession (will be a fault)
        
        // Start second proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        
        // Calculate faults for a range that starts before proving began
        uint256 earlyStart = startBlock - 1000; // 1000 blocks before proving started
        uint256 earlyEnd = startBlock + pdpService.getMaxProvingPeriod() * 2; // End after second period
        
        (uint256 faultCount, uint256 lastConsideredEpoch) = pdpService.calculateFaultsBetweenEpochs(
            proofSetId, 
            earlyStart, 
            earlyEnd
        );
        
        // Should only count faults from when proving started to the end of periods
        // First period wasn't proven, so it's getMaxProvingPeriod() epochs of faults
        // Since we use inclusivity on one end and exclusivity on the other,
        // the actual range is startBlock through (startBlock + getMaxProvingPeriod())
        // which is getMaxProvingPeriod() + 1 epochs
        assertEq(faultCount, pdpService.getMaxProvingPeriod() + 1, "Should only count faults after proving started");
        assertEq(lastConsideredEpoch, startBlock + pdpService.getMaxProvingPeriod(), "Last considered epoch should be end of recorded period");
    }
    
    function testCalculateFaultsCurrentPeriodOverlap() public {
        // Setup initial state
        uint256 startBlock = block.number;
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        
        // First period - don't prove possession (fault)
        
        // Start second proving period
        vm.roll(startBlock + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);

        // Move into the middle of the second period (which is still active/current)
        vm.roll(startBlock + pdpService.getMaxProvingPeriod() + 1000);
        
        // Calculate faults for a range that spans both the completed first period and part of the active second period
        uint256 queryStart = startBlock + pdpService.getMaxProvingPeriod() - 500; // 500 blocks before end of first period
        uint256 queryEnd = startBlock + pdpService.getMaxProvingPeriod() + 1500; // 1500 blocks into second period
        
        (uint256 faultCount, uint256 lastConsideredEpoch) = pdpService.calculateFaultsBetweenEpochs(
            proofSetId, 
            queryStart, 
            queryEnd
        );
        
    
        assertEq(faultCount, 500, "Should only count faults up to the end of completed period");
        
        // Last considered epoch should be the end of the first period
        assertEq(lastConsideredEpoch, startBlock + pdpService.getMaxProvingPeriod(), 
            "Last considered epoch should be the end of the previous period");
    }
}