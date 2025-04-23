// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PDPVerifier, PDPListener} from "./PDPVerifier.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Payments, IArbiter} from "@fws-payments/Payments.sol";

/// @title SimplePDPServiceWithPayments
/// @notice An implementation of PDP Listener with payment integration.
/// @dev This contract extends SimplePDPService by adding payment functionality
/// using the Payments contract. It creates payment rails for storage providers
/// and adjusts payment rates based on storage size. Also implements arbitration
/// to reduce payments for faulted epochs.
contract SimplePDPServiceWithPayments is
    PDPListener,
    IArbiter,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    event FaultRecord(
        uint256 indexed proofSetId,
        uint256 periodsFaulted,
        uint256 deadline
    );
    event ProofSetRailCreated(
        uint256 indexed proofSetId,
        uint256 railId,
        address payer,
        address payee
    );
    event RailRateUpdated(
        uint256 indexed proofSetId,
        uint256 railId,
        uint256 newRate
    );
    event RootMetadataAdded(
        uint256 indexed proofSetId,
        uint256 rootId,
        string metadata
    );

    // Constants
    uint256 public constant NO_CHALLENGE_SCHEDULED = 0;
    uint256 public constant NO_PROVING_DEADLINE = 0;
    uint256 public constant MIB_IN_BYTES = 1024 * 1024; // 1 MiB in bytes
    uint256 public constant BYTES_PER_LEAF = 32; // Each leaf is 32 bytes
    uint256 public constant COMMISSION_MAX_BPS = 10000; // 100% in basis points
    uint256 public constant DEFAULT_LOCKUP_PERIOD = 2880 * 10; // 10 days in epochs
    uint256 public constant GIB_IN_BYTES = MIB_IN_BYTES * 1024; // 1 GiB in bytes
    uint256 public constant EPOCHS_PER_MONTH = 2880 * 30; 

    // Dynamic fee values based on token decimals
    uint256 public PROOFSET_CREATION_FEE; // 0.1 USDFC with correct decimals

    // Token decimals
    uint8 public tokenDecimals;

    // External contract addresses
    address public pdpVerifierAddress;
    address public paymentsContractAddress;
    address public usdFcTokenAddress;

    // Commission rate in basis points (100 = 1%)
    uint256 public operatorCommissionBps;

    // Storage for proof set payment information
    struct ProofSetInfo {
        uint256 railId; // ID of the payment rail
        address payer; // Address paying for storage
        address payee; // SP's beneficiary address
        uint256 commissionBps; // Commission rate for this proof set
        string metadata; // General metadata for the proof set
        string[] rootMetadata; // Array of metadata for each root
        mapping(uint256 => string) rootIdToMetadata; // Mapping from root ID to its metadata
    }

    // Decode structure for proof set creation extra data
    struct ProofSetCreateData {
        string metadata;
        address payer;
    }

    // Mappings
    mapping(uint256 => uint256) public provingDeadlines;
    mapping(uint256 => bool) public provenThisPeriod;
    mapping(uint256 => ProofSetInfo) public proofSetInfo;

    // Mapping from rail ID to proof set ID for arbitration
    mapping(uint256 => uint256) public railToProofSet;

    // Event for arbitration
    event PaymentArbitrated(
        uint256 railId,
        uint256 proofSetId,
        uint256 originalAmount,
        uint256 modifiedAmount,
        uint256 faultedEpochs
    );

    // Track which proving periods have valid proofs (proofSetId => periodId => isProven)
    mapping(uint256 => mapping(uint256 => bool)) public provenPeriods;

    // Track when proving was first activated for each proof set
    mapping(uint256 => uint256) public provingActivationEpoch;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pdpVerifierAddress,
        address _paymentsContractAddress,
        address _usdFcTokenAddress,
        uint256 _initialOperatorCommissionBps
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        require(
            _pdpVerifierAddress != address(0),
            "PDP verifier address cannot be zero"
        );
        require(
            _paymentsContractAddress != address(0),
            "Payments contract address cannot be zero"
        );
        require(
            _usdFcTokenAddress != address(0),
            "USDFC token address cannot be zero"
        );
        require(
            _initialOperatorCommissionBps <= COMMISSION_MAX_BPS,
            "Commission exceeds maximum"
        );

        pdpVerifierAddress = _pdpVerifierAddress;
        paymentsContractAddress = _paymentsContractAddress;
        usdFcTokenAddress = _usdFcTokenAddress;
        operatorCommissionBps = _initialOperatorCommissionBps;

        // Read token decimals from the USDFC token contract
        tokenDecimals = IERC20Metadata(_usdFcTokenAddress).decimals();

        // Initialize the fee constants based on the actual token decimals
        PROOFSET_CREATION_FEE = (1 * 10 ** tokenDecimals) / 10; // 0.1 USDFC
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Updates the default operator commission rate for new proof sets
     * @dev Only callable by the contract owner
     * @param newCommissionBps New commission rate in basis points (100 = 1%)
     */
    function updateOperatorCommission(
        uint256 newCommissionBps
    ) external onlyOwner {
        require(
            newCommissionBps <= COMMISSION_MAX_BPS,
            "Commission exceeds maximum"
        );
        operatorCommissionBps = newCommissionBps;
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
    function thisChallengeWindowStart(
        uint256 setId
    ) public view returns (uint256) {
        if (provingDeadlines[setId] == NO_PROVING_DEADLINE) {
            revert("Proving period not yet initialized");
        }

        uint256 periodsSkipped;
        // Proving period is open 0 skipped periods
        if (block.number <= provingDeadlines[setId]) {
            periodsSkipped = 0;
        } else {
            // Proving period has closed possibly some skipped periods
            periodsSkipped =
                1 +
                (block.number - (provingDeadlines[setId] + 1)) /
                getMaxProvingPeriod();
        }
        return
            provingDeadlines[setId] +
            periodsSkipped *
            getMaxProvingPeriod() -
            challengeWindow();
    }

    // The start of the NEXT OPEN proving period's challenge window
    // Useful for querying before nextProvingPeriod to determine challengeEpoch to submit for nextProvingPeriod
    function nextChallengeWindowStart(
        uint256 setId
    ) public view returns (uint256) {
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
    /**
     * @notice Handles proof set creation by creating a payment rail
     * @dev Called by the PDPVerifier contract when a new proof set is created
     * @param proofSetId The ID of the newly created proof set
     * @param creator The address that created the proof set and will receive payments
     * @param extraData Encoded data containing metadata and payer information
     */
    function proofSetCreated(
        uint256 proofSetId,
        address creator,
        bytes calldata extraData
    ) external {
        // Decode the extra data to get the metadata and payer address
        require(
            extraData.length > 0,
            "Extra data required for proof set creation"
        );
        ProofSetCreateData memory createData = decodeProofSetCreateData(
            extraData
        );

        // Validate the addresses
        require(createData.payer != address(0), "Payer address cannot be zero");
        require(creator != address(0), "Creator address cannot be zero");

        // Initialize the ProofSetInfo struct
        ProofSetInfo storage info = proofSetInfo[proofSetId];
        info.payer = createData.payer;
        info.payee = creator; // Using creator as the payee
        info.metadata = createData.metadata;
        info.commissionBps = operatorCommissionBps; // Use the contract's default commission rate

        // Note: The payer must have pre-approved this contract to spend USDFC tokens before creating the proof set

        // Create the payment rail using the Payments contract
        Payments payments = Payments(paymentsContractAddress);
        uint256 railId = payments.createRail(
            usdFcTokenAddress, // token address
            createData.payer, // from (payer)
            creator, // to (creator)
            address(this), // this contract acts as the arbiter
            operatorCommissionBps // commission rate
        );

        // Store the rail ID
        info.railId = railId;

        // Store reverse mapping from rail ID to proof set ID for arbitration
        railToProofSet[railId] = proofSetId;

        // First, set a lockupFixed value that's at least equal to the one-time payment
        // This is necessary because modifyRailPayment requires that lockupFixed >= oneTimePayment
        payments.modifyRailLockup(
            railId,
            DEFAULT_LOCKUP_PERIOD,
            PROOFSET_CREATION_FEE // lockupFixed equal to the one-time payment amount
        );

        // Charge the one-time proof set creation fee
        // This is a payment from payer to creator of a fixed amount
        payments.modifyRailPayment(
            railId,
            0, // Initial rate is 0, will be updated when roots are added
            PROOFSET_CREATION_FEE // One-time payment amount
        );

        // Emit event for tracking
        emit ProofSetRailCreated(proofSetId, railId, createData.payer, creator);
    }

    // TODO: Payment rail termination; not needed in MVP
    function proofSetDeleted(
        uint256 proofSetId,
        uint256 deletedLeafCount,
        bytes calldata
    ) external {}

    /**
     * @notice Handles roots being added to a proof set and stores associated metadata
     * @dev Called by the PDPVerifier contract when roots are added to a proof set
     * @param proofSetId The ID of the proof set
     * @param firstAdded The ID of the first root added
     * @param rootData Array of root data objects
     * @param extraData Encoded metadata string for the roots
     */
    function rootsAdded(
        uint256 proofSetId,
        uint256 firstAdded,
        PDPVerifier.RootData[] memory rootData,
        bytes calldata extraData
    ) external {
        // Verify the proof set exists in our mapping
        require(
            proofSetInfo[proofSetId].railId != 0,
            "Proof set not registered with payment system"
        );

        // Get the metadata from extra data (simple string in this case)
        string memory metadata = "";
        if (extraData.length > 0) {
            metadata = abi.decode(extraData, (string));
        }

        // Store metadata for each new root
        ProofSetInfo storage info = proofSetInfo[proofSetId];
        for (uint256 i = 0; i < rootData.length; i++) {
            uint256 rootId = firstAdded + i;
            info.rootIdToMetadata[rootId] = metadata;
            emit RootMetadataAdded(proofSetId, rootId, metadata);
        }
    }

    function rootsScheduledRemove(
        uint256 proofSetId,
        uint256[] memory rootIds,
        bytes calldata
    ) external {}

    // possession proven checks for correct challenge count and reverts if too low
    // it also checks that proofs are not late and emits a fault record if so
    function possessionProven(
        uint256 proofSetId,
        uint256 /*challengedLeafCount*/,
        uint256 /*seed*/,
        uint256 challengeCount
    ) external {
        if (provenThisPeriod[proofSetId]) {
            revert(
                "Only one proof of possession allowed per proving period. Open a new proving period."
            );
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
        uint256 currentPeriod = getProvingPeriodForEpoch(
            proofSetId,
            block.number
        );
        provenPeriods[proofSetId][currentPeriod] = true;
    }

    // nextProvingPeriod checks for unsubmitted proof in which case it emits a fault event
    // Additionally it enforces constraints on the update of its state:
    // 1. One update per proving period.
    // 2. Next challenge epoch must fall within the challenge window in the last challengeWindow()
    //    epochs of the proving period.
    //
    // In the payment version, it also updates the payment rate based on the current storage size.
    function nextProvingPeriod(
        uint256 proofSetId,
        uint256 challengeEpoch,
        uint256 leafCount,
        bytes calldata
    ) external {
        // initialize state for new proofset
        if (provingDeadlines[proofSetId] == NO_PROVING_DEADLINE) {
            uint256 firstDeadline = block.number + getMaxProvingPeriod();
            if (
                challengeEpoch < firstDeadline - challengeWindow() ||
                challengeEpoch > firstDeadline
            ) {
                revert(
                    "Next challenge epoch must fall within the next challenge window"
                );
            }
            provingDeadlines[proofSetId] = firstDeadline;
            provenThisPeriod[proofSetId] = false;

            // Initialize the activation epoch when proving first starts
            // This marks when the proof set became active for proving
            provingActivationEpoch[proofSetId] = block.number;

            // Update the payment rate
            updateRailPaymentRate(proofSetId, leafCount);

            return;
        }

        // Revert when proving period not yet open
        // Can only get here if calling nextProvingPeriod multiple times within the same proving period
        uint256 prevDeadline = provingDeadlines[proofSetId] -
            getMaxProvingPeriod();
        if (block.number <= prevDeadline) {
            revert("One call to nextProvingPeriod allowed per proving period");
        }

        uint256 periodsSkipped;
        // Proving period is open 0 skipped periods
        if (block.number <= provingDeadlines[proofSetId]) {
            periodsSkipped = 0;
        } else {
            // Proving period has closed possibly some skipped periods
            periodsSkipped =
                (block.number - (provingDeadlines[proofSetId] + 1)) /
                getMaxProvingPeriod();
        }

        uint256 nextDeadline;
        // the proofset has become empty and provingDeadline is set inactive
        if (challengeEpoch == NO_CHALLENGE_SCHEDULED) {
            nextDeadline = NO_PROVING_DEADLINE;
        } else {
            nextDeadline =
                provingDeadlines[proofSetId] +
                getMaxProvingPeriod() *
                (periodsSkipped + 1);
            if (
                challengeEpoch < nextDeadline - challengeWindow() ||
                challengeEpoch > nextDeadline
            ) {
                revert(
                    "Next challenge epoch must fall within the next challenge window"
                );
            }
        }
        uint256 faultPeriods = periodsSkipped;
        if (!provenThisPeriod[proofSetId]) {
            // include previous unproven period
            faultPeriods += 1;
        }
        if (faultPeriods > 0) {
            emit FaultRecord(
                proofSetId,
                faultPeriods,
                provingDeadlines[proofSetId]
            );
        }

        // Record the status of the current/previous proving period that's ending
        if (provingDeadlines[proofSetId] != NO_PROVING_DEADLINE) {
            // Determine the period ID that just completed
            uint256 completedPeriodId = getProvingPeriodForEpoch(
                proofSetId,
                provingDeadlines[proofSetId] - 1
            );

            // Record whether this period was proven
            provenPeriods[proofSetId][completedPeriodId] = provenThisPeriod[
                proofSetId
            ];
        }

        provingDeadlines[proofSetId] = nextDeadline;
        provenThisPeriod[proofSetId] = false;

        // Update the payment rate based on current proof set size
        updateRailPaymentRate(proofSetId, leafCount);
    }

    function updateRailPaymentRate(
        uint256 proofSetId,
        uint256 leafCount
    ) internal {
        // Revert if no payment rail is configured for this proof set
        require(
            proofSetInfo[proofSetId].railId != 0,
            "No payment rail configured"
        );

        uint256 newRatePerEpoch = 0; // Default to 0 for empty proof sets

        uint256 totalBytes = getProofSetSizeInBytes(leafCount);
        newRatePerEpoch = calculateStorageRatePerEpoch(totalBytes);

        // Update the rail payment rate
        Payments payments = Payments(paymentsContractAddress);
        uint256 railId = proofSetInfo[proofSetId].railId;

        // Call modifyRailPayment with the new rate and no one-time payment
        payments.modifyRailPayment(
            railId,
            newRatePerEpoch,
            0 // No one-time payment during rate update
        );

        emit RailRateUpdated(proofSetId, railId, newRatePerEpoch);
    }

    /**
     * @notice Determines which proving period an epoch belongs to
     * @dev For a given epoch, calculates the period ID based on activation time
     * @param proofSetId The ID of the proof set
     * @param epoch The epoch to check
     * @return The period ID this epoch belongs to, or type(uint256).max if before activation
     */
    function getProvingPeriodForEpoch(
        uint256 proofSetId,
        uint256 epoch
    ) public view returns (uint256) {
        uint256 activationEpoch = provingActivationEpoch[proofSetId];

        // If proving wasn't activated or epoch is before activation
        if (activationEpoch == 0 || epoch < activationEpoch) {
            return type(uint256).max; // Invalid period
        }

        // Calculate periods since activation
        // For example, if activation is at epoch 1000 and proving period is 2880:
        // - Epoch 1000-3879 is period 0
        // - Epoch 3880-6759 is period 1
        // and so on
        return (epoch - activationEpoch) / getMaxProvingPeriod();
    }

    /**
     * @notice Checks if a specific epoch has been proven
     * @dev Returns true only if the epoch belongs to a proven proving period
     * @param proofSetId The ID of the proof set to check
     * @param epoch The epoch to check
     * @return True if the epoch has been proven, false otherwise
     */
    function isEpochProven(
        uint256 proofSetId,
        uint256 epoch
    ) public view returns (bool) {
        // Check if proof set is active
        if (provingActivationEpoch[proofSetId] == 0) {
            return false;
        }

        // Check if this epoch is before activation
        if (epoch < provingActivationEpoch[proofSetId]) {
            return false;
        }

        // Check if this epoch is in the future (beyond current block)
        if (epoch > block.number) {
            return false;
        }

        // Get the period this epoch belongs to
        uint256 periodId = getProvingPeriodForEpoch(proofSetId, epoch);

        // Special case: current ongoing proving period
        uint256 currentPeriod = getProvingPeriodForEpoch(
            proofSetId,
            block.number
        );
        if (periodId == currentPeriod) {
            // For the current period, check if it has been proven already
            return provenThisPeriod[proofSetId];
        }

        // For past periods, check the provenPeriods mapping
        return provenPeriods[proofSetId][periodId];
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculate the per-epoch rate based on total storage size
     * @dev Rate is 2 USDFC per GiB per month. Free if totalBytes < 1 MiB.
     * @param totalBytes Total size of the stored data in bytes
     * @return ratePerEpoch The calculated rate per epoch in the token's smallest unit
     */
    function calculateStorageRatePerEpoch(
        uint256 totalBytes
    ) public view returns (uint256) {
        // Free tier: No charge if storage is less than 1 MiB
        if (totalBytes < MIB_IN_BYTES) {
            return 0;
        }

       
        uint256 numerator = totalBytes * 2 * (10 ** uint256(tokenDecimals));
        uint256 denominator = GIB_IN_BYTES * EPOCHS_PER_MONTH;

        // Ensure denominator is not zero (shouldn't happen with constants)
        require(denominator > 0, "Denominator cannot be zero");

        uint256 ratePerEpoch = numerator / denominator;

        // Ensure minimum rate is 0.00001 USDFC if calculation results in 0 due to rounding,
        // but only if bytes >= 1 MiB (already checked above).
        // This prevents charging 0 for sizes slightly above 1 MiB but below the threshold for a rate of 1 unit.
        if (ratePerEpoch == 0 && totalBytes >= MIB_IN_BYTES) {
             uint256 minRate = (1 * 10 ** uint256(tokenDecimals)) / 100000;
             return minRate;
        }

        return ratePerEpoch;
    }

    /**
     * @notice Decode extra data for proof set creation
     * @param extraData The encoded extra data from PDPVerifier
     * @return decoded The decoded ProofSetCreateData struct
     */
    function decodeProofSetCreateData(
        bytes calldata extraData
    ) internal pure returns (ProofSetCreateData memory) {
        return abi.decode(extraData, (ProofSetCreateData));
    }

    /**
     * @notice Get the total size of a proof set in bytes
     * @param leafCount Number of leaves in the proof set
     * @return totalBytes Total size in bytes
     */
    function getProofSetSizeInBytes(
        uint256 leafCount
    ) public pure returns (uint256) {
        return leafCount * BYTES_PER_LEAF;
    }

    // --- Public getter functions ---

    /**
     * @notice Get the payment rail ID for a proof set
     * @param proofSetId The ID of the proof set
     * @return The payment rail ID, or 0 if not found
     */
    function getProofSetRailId(
        uint256 proofSetId
    ) external view returns (uint256) {
        return proofSetInfo[proofSetId].railId;
    }

    /**
     * @notice Get payer and payee addresses for a proof set
     * @param proofSetId The ID of the proof set
     * @return payer The address paying for storage
     * @return payee The address receiving payments (SP beneficiary)
     */
    function getProofSetParties(
        uint256 proofSetId
    ) external view returns (address payer, address payee) {
        ProofSetInfo storage info = proofSetInfo[proofSetId];
        return (info.payer, info.payee);
    }

    /**
     * @notice Get the metadata for a proof set
     * @param proofSetId The ID of the proof set
     * @return The metadata string
     */
    function getProofSetMetadata(
        uint256 proofSetId
    ) external view returns (string memory) {
        return proofSetInfo[proofSetId].metadata;
    }

    /**
     * @notice Get the metadata for a specific root
     * @param proofSetId The ID of the proof set
     * @param rootId The ID of the root
     * @return The metadata string for the root
     */
    function getRootMetadata(
        uint256 proofSetId,
        uint256 rootId
    ) external view returns (string memory) {
        return proofSetInfo[proofSetId].rootIdToMetadata[rootId];
    }

    /**
     * @notice Arbitrates payment based on faults in the given epoch range
     * @dev Implements the IArbiter interface function
     * @param railId ID of the payment rail
     * @param proposedAmount The originally proposed payment amount
     * @param fromEpoch Starting epoch (exclusive)
     * @param toEpoch Ending epoch (inclusive)
     * @return result The arbitration result with modified amount and settlement information
     */
    function arbitratePayment(
        uint256 railId,
        uint256 proposedAmount,
        uint256 fromEpoch,
        uint256 toEpoch
    ) external override returns (ArbitrationResult memory result) {
        // Get the proof set ID associated with this rail
        uint256 proofSetId = railToProofSet[railId];
        require(proofSetId != 0, "Rail not associated with any proof set");

        // Calculate the total number of epochs in the requested range
        uint256 totalEpochsRequested = toEpoch - fromEpoch;
        require(totalEpochsRequested > 0, "Invalid epoch range");

        // If proving wasn't ever activated for this proof set, don't pay anything
        if (provingActivationEpoch[proofSetId] == 0) {
            return
                ArbitrationResult({
                    modifiedAmount: 0,
                    settleUpto: fromEpoch,
                    note: "Proving never activated for this proof set"
                });
        }

        // Count proven epochs and find the last proven epoch
        uint256 provenEpochCount = 0;
        uint256 lastProvenEpoch = fromEpoch;

        // Check each epoch in the range
        for (uint256 epoch = fromEpoch + 1; epoch <= toEpoch; epoch++) {
            bool isProven = isEpochProven(proofSetId, epoch);

            if (isProven) {
                provenEpochCount++;
                lastProvenEpoch = epoch;
            }
        }

        // If no epochs are proven, we can't settle anything
        if (provenEpochCount == 0) {
            return
                ArbitrationResult({
                    modifiedAmount: 0,
                    settleUpto: fromEpoch,
                    note: "No proven epochs in the requested range"
                });
        }

        // Calculate the modified amount based on proven epochs
        uint256 modifiedAmount = (proposedAmount * provenEpochCount) /
            totalEpochsRequested;

        // Calculate how many epochs were not proven (faulted)
        uint256 faultedEpochs = totalEpochsRequested - provenEpochCount;

        // Emit event for logging
        emit PaymentArbitrated(
            railId,
            proofSetId,
            proposedAmount,
            modifiedAmount,
            faultedEpochs
        );

        return
            ArbitrationResult({
                modifiedAmount: modifiedAmount,
                settleUpto: lastProvenEpoch, // Settle up to the last proven epoch
                note: ""
            });
    }
}
