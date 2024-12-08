// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PDPVerifier, PDPListener} from "./PDPVerifier.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

// PDPRecordKeeper tracks PDP operations.  It is used as a base contract for PDPListeners
// in order to give users the capability to consume events async.
contract PDPRecordKeeper {
    enum OperationType {
        NONE,
        CREATE,
        DELETE,
        ADD,
        REMOVE_SCHEDULED,
        PROVE_POSSESSION,
        NEXT_PROVING_PERIOD
    }    

    // Struct to store event details
    struct EventRecord {
        uint64 epoch;
        uint256 proofSetId;
        OperationType operationType;
        bytes extraData;
    }

    // Eth event emitted when a new record is added
    event RecordAdded(uint256 indexed proofSetId, uint64 epoch, OperationType operationType);

    // Mapping to store events for each proof set
    mapping(uint256 => EventRecord[]) public proofSetEvents;

    function receiveProofSetEvent(uint256 proofSetId, OperationType operationType, bytes memory extraData ) internal returns(uint256) {
        uint64 epoch = uint64(block.number);
        EventRecord memory newRecord = EventRecord({
            epoch: epoch,
            proofSetId: proofSetId,
            operationType: operationType,
            extraData: extraData
        });
        proofSetEvents[proofSetId].push(newRecord);
        emit RecordAdded(proofSetId, epoch, operationType);
        return proofSetEvents[proofSetId].length - 1;
    }

    // Function to get the number of events for a proof set
    function getEventCount(uint256 proofSetId) external view returns (uint256) {
        return proofSetEvents[proofSetId].length;
    }

    // Function to get a specific event for a proof set
    function getEvent(uint256 proofSetId, uint256 eventIndex)
        external
        view
        returns (EventRecord memory)
    {
        require(eventIndex < proofSetEvents[proofSetId].length, "Event index out of bounds");
        return proofSetEvents[proofSetId][eventIndex];
    }

    // Function to get all events for a proof set
    function listEvents(uint256 proofSetId) external view returns (EventRecord[] memory) {
        return proofSetEvents[proofSetId];
    }
}

// SimplePDPServiceApplication is a default implementation of a PDP Listener
// It maintains a record of all events that have occurred in the PDP service,
// and provides a way to query these events.
// This contract only supports one PDP service caller, set in the constructor.
contract SimplePDPService is PDPListener, PDPRecordKeeper, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    event FaultRecord(uint256 periodsFaulted);

    // The address of the PDP verifier contract that is allowed to call this contract
    address public pdpVerifierAddress;
    mapping(uint256 => uint256) public provingDeadlines;
    mapping(uint256 => bool) public provenThisPeriod;

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
     _disableInitializers();
    }

    function initialize(address _pdpVerifierAddress) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        require(_pdpVerifierAddress != address(0), "PDP verifier address cannot be zero");
        pdpVerifierAddress = _pdpVerifierAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Modifier to ensure only the PDP verifier contract can call certain functions
    modifier onlyPDPVerifier() {
        require(msg.sender == pdpVerifierAddress, "Caller is not the PDP verifier");
        _;
    }

    // SLA specification functions setting values for PDP service providers
    // Max number of epochs between two consecutive proofs
    function getMaxProvingPeriod() public pure returns (uint64) {
        return 2880;
    }

    // Number of epochs at the end of a proving period during which a
    // proof of possession can be submitted
    function challengeWindow() public pure returns (uint256) {
        return 60;
    }

    // The start of the challenge window for the current proving period
    function thisChallengeWindowStart(uint256 setId) public view returns (uint256) {
        if (provingDeadlines[setId] == 0) {
            revert("Proving not yet started");
        }

        uint256 periodsSkipped;
        // Proving period is open 0 skipped periods
        if (block.number <= provingDeadlines[setId]) {
            periodsSkipped = 0;
        } else { // Proving period has closed possibly some skipped periods
            periodsSkipped = 1 + (block.number - (provingDeadlines[setId] + 1)) / getMaxProvingPeriod();
        }
        return provingDeadlines[setId] + periodsSkipped*getMaxProvingPeriod() - challengeWindow();
    }

    // The start of the NEXT OPEN proving period's challenge window
    // Useful for querying before nextProvingPeriod to determine challengeEpoch to submit for nextProvingPeriod
    function nextChallengeWindowStart(uint256 setId) public view returns (uint256) {
        if (provingDeadlines[setId] == 0) {
            revert("Proving not yet started");
        }
        // If the current period is open this is the next period's challenge window
        if (block.number <= provingDeadlines[setId]) {
            return thisChallengeWindowStart(setId) + getMaxProvingPeriod();
        }
        // If the current period is not yet open this is the current period's challenge window
        return thisChallengeWindowStart(setId);
    }

    // Challenges / merkle inclusion proofs provided per proof set
    function getChallengesPerProof() public pure returns (uint64) {
        return 5;
    }

    // Listener interface methods
    // Note we just drop the user defined extraData as this contract has no use for it
    function proofSetCreated(uint256 proofSetId, address creator, bytes calldata) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.CREATE, abi.encode(creator));
    }

    function proofSetDeleted(uint256 proofSetId, uint256 deletedLeafCount, bytes calldata) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.DELETE, abi.encode(deletedLeafCount));
    }

    function rootsAdded(uint256 proofSetId, uint256 firstAdded, PDPVerifier.RootData[] memory rootData, bytes calldata) external onlyPDPVerifier {
        if (firstAdded == 0) {
            provingDeadlines[proofSetId] = block.number + getMaxProvingPeriod();
        }
        receiveProofSetEvent(proofSetId, OperationType.ADD, abi.encode(firstAdded, rootData));
    }

    function rootsScheduledRemove(uint256 proofSetId, uint256[] memory rootIds, bytes calldata) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.REMOVE_SCHEDULED, abi.encode(rootIds));
    }

    // possession proven checks for correct challenge count and reverts if too low
    // it also checks that proofs are not late and emits a fault record if so
    function possessionProven(uint256 proofSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.PROVE_POSSESSION, abi.encode(challengedLeafCount, seed, challengeCount));
        if (provenThisPeriod[proofSetId]) { 
            revert("Only one proof of possession allowed per proving period. Open a new proving period."); 
        }
        if (challengeCount < getChallengesPerProof()) {
            revert("Invalid challenge count < 5");
        }
        // check for proof outside of proving period
        if (provingDeadlines[proofSetId] < block.number) {
            revert("Current proving period passed. Open a new proving period.");
        } 
        if (provingDeadlines[proofSetId] - getMaxProvingPeriod() >= block.number) {
            revert("Too early. Wait for proving period to open");
        }
        provenThisPeriod[proofSetId] = true;
    }

    // nextProvingPeriod checks for unsubmitted proof and emits a fault if so
    function nextProvingPeriod(uint256 proofSetId, uint256 challengeEpoch, uint256 leafCount, bytes calldata) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.NEXT_PROVING_PERIOD, abi.encode(challengeEpoch, leafCount));
        // Noop when proving period not yet open
        // Can only get here if calling nextProvingPeriod multiple times within the same proving period
        uint256 prevDeadline = provingDeadlines[proofSetId] - getMaxProvingPeriod();
        if (block.number <= prevDeadline) {
            revert("One call to nextProvingPeriod allowed per proving period");
        }

        uint256 periodsSkipped;
        // Proving period is open 0 skipped periods
        if (block.number <= provingDeadlines[proofSetId]) {
            periodsSkipped = 0;
        } else { // Proving period has closed possibly some skipped periods
            periodsSkipped = (block.number - (provingDeadlines[proofSetId] + 1)) / getMaxProvingPeriod();
        }
        // ensure next challenge epoch falls within the next challenge window.
        // The next challenge window immediately precedes the next deadline
        uint256 nextDeadline = provingDeadlines[proofSetId] + getMaxProvingPeriod()*(periodsSkipped+1);
        if (challengeEpoch < nextDeadline - challengeWindow() || challengeEpoch > nextDeadline) {
            revert("Next challenge epoch must fall within the next challenge window");
        }
        uint256 faultPeriods = periodsSkipped;
        if (!provenThisPeriod[proofSetId]) { 
            // include previous unproven period 
            faultPeriods += 1;
        }
        if (faultPeriods > 0) {
            emit FaultRecord(faultPeriods);
        }
        provingDeadlines[proofSetId] = nextDeadline;
        provenThisPeriod[proofSetId] = false;
    }
}
