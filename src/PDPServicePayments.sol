// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PDPVerifier, PDPListener} from "./PDPVerifier.sol";
import {SimplePDPService} from "./SimplePDPService.sol"; // Import SimplePDPService
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface for the Payments contract
interface Payments {
    function createRail(
        address token,
        address from,
        address to,
        address arbiter
    ) external returns (uint256);

    function modifyRailPayment(
        uint256 railId,
        uint256 newRate,
        uint256 oneTimePayment
    ) external;

    function modifyRailLockup(
        uint256 railId,
        uint256 period,
        uint256 lockupFixed
    ) external;
}

// Interface for Arbiter (required by Payments contract, even if unused here for now)
interface IArbiter {
    struct ArbitrationResult {
        uint256 modifiedAmount;
        uint256 settleUpto;
        string note;
    }

    function arbitratePayment(
        uint256 railId,
        uint256 proposedAmount,
        uint256 fromEpoch,
        uint256 toEpoch
    ) external returns (ArbitrationResult memory result);
}

/// @title PDPServicePayments
/// @notice A PDP Listener that integrates with the Payments contract
/// @dev Uses SimplePDPService internally for core proof tracking.
contract PDPServicePayments is
    PDPListener,
    IArbiter,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    uint256 public constant RATE_PER_GIB_PER_MONTH = 2e18; // 2 usdFc per GiB per month
    uint256 public constant ONE_MONTH_EPOCHS = 2880 * 30; // Approx 30 days in epochs
    uint256 public constant PROOF_SET_CREATION_FEE = 1e18; // 1 usdFc per proof set creation
    uint256 public constant GIB_IN_BYTES = 1024 * 1024 * 1024; // 1 GiB in bytes
    uint256 public constant LEAF_SIZE = 32;

    address public pdpVerifierAddress;
    address public paymentsAddress;
    address public usdFcAddress;
    address public simplePDPServiceAddress;

    // Storage provider address -> Payee address
    mapping(address => address) public providerPayeeAddresses;

    // Struct for individual root information
    struct RootInfo {
        uint256 rootId;
        string metadata;
    }

    struct ProofSetData {
        uint256 railId;
        address payer;
        address payee;
        string metadata;
        uint256 currentSizeInBytes; // Tracks the size based on leaves/roots added/removed
        RootInfo[] roots;
    }

    // Consolidated mapping: proofSetId => ProofSetData
    mapping(uint256 => ProofSetData) public proofSetData;

    // --- Initialization ---
    function initialize(
        address _pdpVerifierAddress,
        address _paymentsAddress,
        address _usdFcAddress,
        address _simplePDPServiceAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        require(
            _pdpVerifierAddress != address(0),
            "failed to initialize: PDP Verifier address cannot be zero"
        );
        require(
            _paymentsAddress != address(0),
            "failed to initialize: Payments address cannot be zero"
        );
        require(
            _usdFcAddress != address(0),
            "failed to initialize: usdFc address cannot be zero"
        );
        require(
            _simplePDPServiceAddress != address(0),
            "failed to initialize: SimplePDPService address cannot be zero"
        );

        pdpVerifierAddress = _pdpVerifierAddress;
        paymentsAddress = _paymentsAddress;
        usdFcAddress = _usdFcAddress;
        simplePDPServiceAddress = _simplePDPServiceAddress;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // Modifier to ensure only the PDP verifier contract can call certain functions
    modifier onlyPDPVerifier() {
        require(
            msg.sender == pdpVerifierAddress,
            "failed to authorize: caller is not the PDP verifier"
        );
        _;
    }

    function setPayeeAddress(address payee) external {
        require(
            payee != address(0),
            "failed to set payee: payee address cannot be zero"
        );
        providerPayeeAddresses[msg.sender] = payee;
    }

    function getPayeeAddress(
        address providerAddress
    ) public view returns (address) {
        require(
            providerAddress != address(0),
            "failed to get payee: provider address cannot be zero"
        );
        address payee = providerPayeeAddresses[providerAddress];
        return payee;
    }

    function getRailId(uint256 proofSetId) external view returns (uint256) {
        uint256 railId = proofSetData[proofSetId].railId;
        require(
            railId != 0,
            "failed to get rail ID: no rail found for this proof set"
        );
        return railId;
    }

    function getProofSetPaymentInfo(
        uint256 proofSetId
    )
        external
        view
        returns (
            uint256 railId,
            address payer,
            address payee,
            string memory metadata
        )
    {
        ProofSetData storage data = proofSetData[proofSetId];
        require(
            data.payer != address(0),
            "failed to get info: no data found for this proof set"
        );
        return (data.railId, data.payer, data.payee, data.metadata);
    }

    function calculateRateFromSize(
        uint256 sizeInBytes
    ) public pure returns (uint256) {
        // Check for zero division
        if (sizeInBytes == 0 || GIB_IN_BYTES == 0 || ONE_MONTH_EPOCHS == 0) {
            return 0;
        }
        // Calculate rate per month first to avoid precision loss
        uint256 ratePerMonth = (sizeInBytes * RATE_PER_GIB_PER_MONTH) /
            GIB_IN_BYTES;
        // Then calculate rate per epoch
        return ratePerMonth / ONE_MONTH_EPOCHS;
    }

    // --- Listener interface methods implementation (using composition) ---

    function proofSetCreated(
        uint256 proofSetId,
        address creator,
        bytes calldata extraData
    ) external override onlyPDPVerifier {
        // Payment logic first
        (string memory metadata, address payer) = abi.decode(
            extraData,
            (string, address)
        );
        require(
            payer != address(0),
            "failed to create proof set: payer address cannot be zero"
        );

        // Use 'this' contract as the immediate payee for the rail
        address railPayee = address(this);
        Payments payments = Payments(paymentsAddress);
        uint256 railId = payments.createRail(
            usdFcAddress,
            payer,
            railPayee,
            address(0) // No arbiter for now
        );
        require(railId != 0, "failed to create payment rail");

        // Initialize ProofSetData
        ProofSetData storage data = proofSetData[proofSetId];
        data.railId = railId;
        data.payer = payer;
        data.metadata = metadata;
        data.currentSizeInBytes = 0; // Initial size is zero

        address payee = providerPayeeAddresses[creator];
        require(
            payee != address(0),
            "failed to create proof set: payee address not configured"
        );

        // Set payee to the creator's payee address
        data.payee = payee;

        // Configure rail lockup and initial fee
        payments.modifyRailLockup(
            railId,
            ONE_MONTH_EPOCHS,
            PROOF_SET_CREATION_FEE
        );
        try
            payments.modifyRailPayment(railId, 0, PROOF_SET_CREATION_FEE)
        {} catch {
            revert("failed to process proof set creation fee");
        }

        // Delegate to SimplePDPService
        SimplePDPService(simplePDPServiceAddress).proofSetCreated(
            proofSetId,
            creator,
            extraData
        );
    }

    // TODO: Terminate Rail and state cleanup
    function proofSetDeleted(
        uint256 proofSetId,
        uint256 deletedLeafCount, // Note: deletedLeafCount not directly used in this logic
        bytes calldata extraData
    ) external override onlyPDPVerifier {
        // Delegate to SimplePDPService
        SimplePDPService(simplePDPServiceAddress).proofSetDeleted(
            proofSetId,
            deletedLeafCount,
            extraData
        );
    }

    function rootsAdded(
        uint256 proofSetId,
        uint256 firstAddedRootId,
        PDPVerifier.RootData[] memory addedRootsData, // Renamed for clarity
        bytes calldata extraData // Contains root name(s) - assuming single name for batch
    ) external override onlyPDPVerifier {
        uint256 railId = proofSetData[proofSetId].railId;
        require(
            railId != 0,
            "failed to add roots: no rail found for this proof set"
        );

        // Decode the root name from extraData
        string memory rootName = abi.decode(extraData, (string));

        ProofSetData storage data = proofSetData[proofSetId];
        require(
            data.payer != address(0),
            "failed to add roots: proof set data not found"
        );

        uint256 totalNewSize = 0;
        for (uint256 i = 0; i < addedRootsData.length; i++) {
            uint256 currentRootId = firstAddedRootId + i;

            uint256 currentRawSize = addedRootsData[i].rawSize; // Placeholder: Use actual field name

            // Add root info to the array
            data.roots.push(
                RootInfo({
                    rootId: currentRootId,
                    metadata: rootName // Apply the same name to all roots in the batch
                })
            );
            totalNewSize += currentRawSize;
        }

        // Update the total size tracked for payment calculation
        data.currentSizeInBytes += totalNewSize;

        // Calculate and update the payment rate on the rail
        uint256 newRate = calculateRateFromSize(data.currentSizeInBytes);
        try
            Payments(paymentsAddress).modifyRailPayment(railId, newRate, 0)
        {} catch {
            revert("failed to update payment rate after adding roots");
        }

        // Delegate to SimplePDPService
        SimplePDPService(simplePDPServiceAddress).rootsAdded(
            proofSetId,
            firstAddedRootId,
            addedRootsData,
            extraData
        );
    }

    function rootsScheduledRemove(
        uint256 proofSetId,
        uint256[] memory rootIds,
        bytes calldata extraData
    ) external override onlyPDPVerifier {
        // Payment logic: Size/rate adjustment happens in nextProvingPeriod based on leafCount.
        // Delegate to SimplePDPService
        SimplePDPService(simplePDPServiceAddress).rootsScheduledRemove(
            proofSetId,
            rootIds,
            extraData
        );
    }

    function possessionProven(
        uint256 proofSetId,
        uint256 challengedLeafCount,
        uint256 seed,
        uint256 challengeCount
    ) external override onlyPDPVerifier {
        // No direct payment logic triggered by proof itself.

        // Delegate to SimplePDPService for core proof tracking
        SimplePDPService(simplePDPServiceAddress).possessionProven(
            proofSetId,
            challengedLeafCount,
            seed,
            challengeCount
        );
    }

    function nextProvingPeriod(
        uint256 proofSetId,
        uint256 challengeEpoch,
        uint256 leafCount, // This reflects the *current* valid leaf count after removals
        bytes calldata extraData
    ) external override onlyPDPVerifier {
        uint256 railId = proofSetData[proofSetId].railId;
        ProofSetData storage data = proofSetData[proofSetId];

        // Check if proof set exists (it should, otherwise SimplePDPService call would likely fail)
        // require(data.payer != address(0), "failed in next proving period: proof set not found");

        // Calculate the expected size based on the current leaf count
        uint256 newSizeInBytes = leafCount * LEAF_SIZE;

        // Update payment rate only if the size has changed and a rail exists
        if (newSizeInBytes != data.currentSizeInBytes && railId != 0) {
            data.currentSizeInBytes = newSizeInBytes; // Update tracked size
            uint256 newRate = calculateRateFromSize(newSizeInBytes);
            try
                Payments(paymentsAddress).modifyRailPayment(railId, newRate, 0)
            {} catch {
                // Suppress error? Or revert? Reverting might halt period advancement.
                // For now, let's allow period advancement even if rate update fails.
                // Consider adding logging or an event here.
            }
        }

        // Delegate to SimplePDPService for core period advancement logic
        SimplePDPService(simplePDPServiceAddress).nextProvingPeriod(
            proofSetId,
            challengeEpoch,
            leafCount,
            extraData
        );
    }

    // --- IArbiter implementation ---
    function arbitratePayment(
        uint256 railId, // railId is implicitly linked to a proofSetId via proofSetToRailId
        uint256 proposedAmount,
        uint256 fromEpoch,
        uint256 toEpoch
    ) external view override returns (ArbitrationResult memory result) {
        require(
            msg.sender == paymentsAddress,
            "failed to arbitrate: caller is not the payments contract"
        );
        // Basic passthrough arbitration logic
        // TODO: Implement actual arbitration logic if needed, potentially based on proofSetData
        return
            ArbitrationResult({
                modifiedAmount: proposedAmount,
                settleUpto: toEpoch,
                note: "Standard approval (arbitration logic not implemented)"
            });
    }

    // TODO : Settlement and Arbitration
}
