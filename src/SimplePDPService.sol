// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PDPVerifier, PDPListener} from "./PDPVerifier.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

// PDPRecordKeeper tracks PDP operations.  It is used as a base contract for PDPListeners
// in order to give users the capability to consume events async.
/// @title PDPRecordKeeper
/// @dev This contract is unused by the SimplePDPService as it is too expensive. 
/// we've kept it here for future reference and testing.
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

/// @title SimplePDPService
/// @notice A default implementation of a PDP Listener.
/// @dev This contract only supports one PDP service caller, set in the constructor,
/// The primary purpose of this contract is to 
/// 1. Enforce a proof count of 5 proofs per proof set proving period.
/// 2. Provide a reliable way to report faults to users.
contract SimplePDPService is PDPListener, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    event FaultRecord(uint256 indexed proofSetId, uint256 periodsFaulted, uint256 deadline);

    uint256 public constant NO_CHALLENGE_SCHEDULED = 0;
    uint256 public constant NO_PROVING_DEADLINE = 0;

    // The address of the PDP verifier contract that is allowed to call this contract
    address public pdpVerifierAddress;
    mapping(uint256 => uint256) public provingDeadlines;
    mapping(uint256 => bool) public provenThisPeriod;
    
    struct ProvingPeriodStatus {
        bool proven;               // Whether this period had a successful proof
        uint256 startEpoch;        // First epoch in this period (inclusive)
        uint256 endEpoch;          // Last epoch in this period (inclusive)
    }

    // Main storage mapping - records status for each completed proving period
    mapping(uint256 => mapping(uint256 => ProvingPeriodStatus)) public provingPeriodHistory;

    // Track the sequential ID of each period for efficient lookup
    mapping(uint256 => uint256) public lastRecordedPeriodId;

    // Track when proving was first activated for each proof set
    mapping(uint256 => uint256) public provingActivationEpoch;

    // Track the end epoch of the last recorded period (helps with gap detection)
    mapping(uint256 => uint256) public lastRecordedPeriodEndEpoch;

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

    // Initial value for challenge window start
    // Can be used for first call to nextProvingPeriod
    function initChallengeWindowStart() public view returns (uint256) {
        return block.number + getMaxProvingPeriod() - challengeWindow();
    }

    // The start of the challenge window for the current proving period
    function thisChallengeWindowStart(uint256 setId) public view returns (uint256) {
        if (provingDeadlines[setId] == NO_PROVING_DEADLINE) {
            revert("Proving period not yet initialized");
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
        if (provingDeadlines[setId] == NO_PROVING_DEADLINE) {
            revert("Proving period not yet initialized");
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
    // Note many of these are noops as they are not important for the SimplePDPService's functionality
    // of enforcing proof contraints and reporting faults.
    // Note we generally just drop the user defined extraData as this contract has no use for it
    function proofSetCreated(uint256 proofSetId, address creator, bytes calldata) external onlyPDPVerifier {}

    function proofSetDeleted(uint256 proofSetId, uint256 deletedLeafCount, bytes calldata) external onlyPDPVerifier {}

    function rootsAdded(uint256 proofSetId, uint256 firstAdded, PDPVerifier.RootData[] memory rootData, bytes calldata) external onlyPDPVerifier {}

    function rootsScheduledRemove(uint256 proofSetId, uint256[] memory rootIds, bytes calldata) external onlyPDPVerifier {}

    // possession proven checks for correct challenge count and reverts if too low
    // it also checks that proofs are not late and emits a fault record if so
    function possessionProven(uint256 proofSetId, uint256 /*challengedLeafCount*/, uint256 /*seed*/, uint256 challengeCount) external onlyPDPVerifier {
        if (provenThisPeriod[proofSetId]) {
            revert("Only one proof of possession allowed per proving period. Open a new proving period.");
        }
        if (challengeCount < getChallengesPerProof()) {
            revert("Invalid challenge count < 5");
        }
        if (provingDeadlines[proofSetId] == NO_PROVING_DEADLINE) {
            revert("Proving not yet started");
        }
        // check for proof outside of challenge window
        if (provingDeadlines[proofSetId] < block.number) {
            revert("Current proving period passed. Open a new proving period.");
        }

        if (provingDeadlines[proofSetId] - challengeWindow() > block.number) {
            revert("Too early. Wait for challenge window to open");
        }
        provenThisPeriod[proofSetId] = true;
    }

    // nextProvingPeriod checks for unsubmitted proof in which case it emits a fault event
    // Additionally it enforces constraints on the update of its state: 
    // 1. One update per proving period.
    // 2. Next challenge epoch must fall within the challenge window in the last challengeWindow()
    //    epochs of the proving period.
    function nextProvingPeriod(uint256 proofSetId, uint256 challengeEpoch, uint256 /*leafCount*/, bytes calldata) external onlyPDPVerifier {
        // initialize state for new proofset
        if (provingDeadlines[proofSetId] == NO_PROVING_DEADLINE) {
            uint256 firstDeadline = block.number + getMaxProvingPeriod();
            if (challengeEpoch < firstDeadline - challengeWindow() || challengeEpoch > firstDeadline) {
                revert("Next challenge epoch must fall within the next challenge window");
            }
            provingDeadlines[proofSetId] = firstDeadline;
            provenThisPeriod[proofSetId] = false;
            
            // Initialize the activation epoch when proving first starts
            // This marks when the proof set became active for proving
            provingActivationEpoch[proofSetId] = block.number;
            return;
        }

        // Revert when proving period not yet open
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

        uint256 nextDeadline;
        // the proofset has become empty and provingDeadline is set inactive
        if (challengeEpoch == NO_CHALLENGE_SCHEDULED) {
            nextDeadline = NO_PROVING_DEADLINE;
        } else {
            nextDeadline = provingDeadlines[proofSetId] + getMaxProvingPeriod()*(periodsSkipped+1);
            if (challengeEpoch < nextDeadline - challengeWindow() || challengeEpoch > nextDeadline) {
                revert("Next challenge epoch must fall within the next challenge window");
            }
        }
        uint256 faultPeriods = periodsSkipped;
        if (!provenThisPeriod[proofSetId]) {
            // include previous unproven period
            faultPeriods += 1;
        }
        if (faultPeriods > 0) {
            emit FaultRecord(proofSetId, faultPeriods, provingDeadlines[proofSetId]);
        }
        
        // Record the status of the current/previous proving period that's ending
        // This is done before updating the state for the next period
        if (provingDeadlines[proofSetId] != NO_PROVING_DEADLINE) {
            uint256 periodId = lastRecordedPeriodId[proofSetId];
            uint256 periodStart;
            uint256 periodEnd = provingDeadlines[proofSetId];
            
            // Determine the start epoch for this period
            if (periodId == 0 || lastRecordedPeriodEndEpoch[proofSetId] + 1 < periodEnd - getMaxProvingPeriod()) {
                // First period or gap detected - use the actual start
                periodStart = periodEnd - getMaxProvingPeriod();
            } else {
                // Normal sequential period - use end of previous period + 1
                periodStart = lastRecordedPeriodEndEpoch[proofSetId] + 1;
            }
            
            // Only record if this is a valid period
            if (periodEnd >= periodStart) {
                // Record the proving period status
                provingPeriodHistory[proofSetId][periodId] = ProvingPeriodStatus({
                    proven: provenThisPeriod[proofSetId],
                    startEpoch: periodStart,
                    endEpoch: periodEnd
                });
                
                // Update tracking variables
                lastRecordedPeriodEndEpoch[proofSetId] = periodEnd;
                lastRecordedPeriodId[proofSetId]++;
            }
        }
        
        provingDeadlines[proofSetId] = nextDeadline;
        provenThisPeriod[proofSetId] = false;
    }
    
    /**
     * @notice Calculate the number of faulted epochs between two specified epochs
     * @dev Returns the count of epochs where the provider failed to prove possession
     *      Only counts completed proving periods and excludes epochs before proving activation
     *      fromEpoch is exclusive, toEpoch is inclusive
     * @param proofSetId The ID of the proof set to check for faults
     * @param fromEpoch The starting epoch (exclusive)
     * @param toEpoch The ending epoch (inclusive)
     * @return faultCount The number of epochs that had faults
     * @return lastConsideredEpoch The last epoch that was included in the calculation
     */
    function calculateFaultsBetweenEpochs(uint256 proofSetId, uint256 fromEpoch, uint256 toEpoch) 
        public view returns (uint256 faultCount, uint256 lastConsideredEpoch)
    {
        // Skip if proving wasn't active or range is invalid
        if (provingActivationEpoch[proofSetId] == 0 || fromEpoch >= toEpoch) {
            return (0, fromEpoch);
        }
        
        // Never consider epochs before proving was activated
        // Since fromEpoch is exclusive, we compare with activation - 1
        fromEpoch = max(fromEpoch, provingActivationEpoch[proofSetId] - 1);
        
        // Determine the most recent period that has completed
        uint256 mostRecentCompletedPeriodId = lastRecordedPeriodId[proofSetId] > 0 ? 
                                             lastRecordedPeriodId[proofSetId] - 1 : 0;
        
        // If no periods recorded yet, use activation epoch as boundary
        if (lastRecordedPeriodId[proofSetId] == 0) {
            return (0, fromEpoch);
        }
        
        // Get the last recorded proving period
        ProvingPeriodStatus memory lastPeriod = provingPeriodHistory[proofSetId][mostRecentCompletedPeriodId];
        lastConsideredEpoch = lastPeriod.endEpoch;
        
        // Don't look beyond the requested range
        lastConsideredEpoch = min(lastConsideredEpoch, toEpoch);
        
        // Skip if we're not looking at any completed periods
        if (fromEpoch >= lastConsideredEpoch) {
            return (0, lastConsideredEpoch);
        }
        
        // Count faults in each period that overlaps our range
        faultCount = 0;
        for (uint256 i = 0; i < lastRecordedPeriodId[proofSetId]; i++) {
            ProvingPeriodStatus memory period = provingPeriodHistory[proofSetId][i];
            
            // Skip if period ended before our range starts or started after our range ends
            if (period.endEpoch <= fromEpoch || period.startEpoch > lastConsideredEpoch) {
                continue;
            }
            
            // If this period wasn't proven, add the number of epochs that fall in our range
            if (!period.proven) {
                uint256 overlapStart = max(fromEpoch + 1, period.startEpoch);  // +1 makes fromEpoch exclusive
                uint256 overlapEnd = min(lastConsideredEpoch, period.endEpoch);
                
                // Count epochs in this faulty period that overlap our query range
                if (overlapEnd >= overlapStart) {  // Ensure valid range
                    faultCount += (overlapEnd - overlapStart + 1);  // +1 because both ends are inclusive
                }
            }
        }
        
        return (faultCount, lastConsideredEpoch);
    }
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
