// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {BitOps} from "./BitOps.sol";
import {Cids} from "./Cids.sol";
import {MerkleVerify} from "./Proofs.sol";
import {PDPFees} from "./Fees.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {FVMPay} from "fvm-solidity/FVMPay.sol";
import {FVMRandom} from "fvm-solidity/FVMRandom.sol";
import {IPDPTypes} from "./interfaces/IPDPTypes.sol";
import {
    PieceMetadata,
    PieceMetadataLibrary,
    LEAF_COUNT_MAX,
    SUM_TREE_MAX,
    PieceMetadataOverflow
} from "./PieceMetadata.sol";

/// @title PDPListener
/// @notice Interface for PDP Service applications managing data storage.
/// @dev This interface exists to provide an extensible hook for applications to use the PDP verification contract
/// to implement data storage applications.
interface PDPListener {
    function dataSetCreated(uint256 dataSetId, address creator, bytes calldata extraData) external;
    function dataSetDeleted(uint256 dataSetId, uint256 deletedLeafCount, bytes calldata extraData) external;
    function piecesAdded(uint256 dataSetId, uint256 firstAdded, Cids.Cid[] memory pieceData, bytes calldata extraData)
        external;
    function piecesScheduledRemove(uint256 dataSetId, uint256[] memory pieceIds, bytes calldata extraData) external;
    // Note: extraData not included as proving messages conceptually always originate from the SP
    function possessionProven(uint256 dataSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount)
        external;
    function nextProvingPeriod(uint256 dataSetId, uint256 challengeEpoch, uint256 leafCount, bytes calldata extraData)
        external;
    /// @notice Called when data set storage provider is changed in PDPVerifier.
    function storageProviderChanged(
        uint256 dataSetId,
        address oldStorageProvider,
        address newStorageProvider,
        bytes calldata extraData
    ) external;
}

uint256 constant NEW_DATA_SET_SENTINEL = 0;
// Defaults
uint256 constant NO_CHALLENGE_SCHEDULED = 0;
uint256 constant NO_PROVEN_EPOCH = 0;

contract PDPVerifier is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Constants
    uint256 public constant MAX_PIECE_SIZE_LOG2 = 50;
    uint256 public constant MAX_ENQUEUED_REMOVALS = 2000;
    uint256 private constant PIECE_ID_EVENT_BATCH_SIZE = 100;

    // Cleanup
    uint256 private constant CLEANUP_MODE_SENTINEL = type(uint256).max;
    uint256 public constant INACTIVITY_WINDOW = 86400;

    // Upgrade sequence number, used by Initializable.reinitializer
    uint64 private immutable REINITIALIZER_VERSION;

    // Events
    event DataSetCreated(uint256 indexed setId, address indexed storageProvider);
    event StorageProviderChanged(
        uint256 indexed setId, address indexed oldStorageProvider, address indexed newStorageProvider
    );
    event DataSetDeleted(uint256 indexed setId, uint256 deletedLeafCount);
    event DataSetEmpty(uint256 indexed setId);

    event PiecesAdded(uint256 indexed setId, uint256[] pieceIds, Cids.Cid[] pieceCids);
    event PiecesScheduledForRemoval(uint256 indexed setId, uint256[] pieceIds);
    event PiecesRemoved(uint256 indexed setId, uint256[] pieceIds);

    event ProofFeePaid(uint256 indexed setId, uint256 fee);
    event FeeUpdateProposed(uint256 currentFee, uint256 newFee, uint256 effectiveTime);

    event PossessionProven(uint256 indexed setId, IPDPTypes.PieceIdAndOffset[] challenges);
    event NextProvingPeriod(uint256 indexed setId, uint256 challengeEpoch, uint256 leafCount);
    // Types
    // State fields
    /*
    A data set is the metadata required for tracking data for proof of possession.
    It maintains a list of CIDs of data to be proven and metadata needed to
    add and remove data to the set and prove possession efficiently.

    ** logical structure of the data set**
    /*
    struct DataSet {
        Cid[] pieces;
        uint256[] leafCounts;
        uint256[] sumTree;
        uint256 leafCount;
        address storageProvider;
        address proposed storageProvider;
        nextPieceID uint64;
        nextChallengeEpoch: uint64;
        listenerAddress: address;
        challengeRange: uint256
        enqueuedRemovals: uint256[]
    }
    ** PDP Verifier contract tracks many possible data sets **
    []DataSet dataSets

    /*
    The legacy piece mappings below are retained exclusively to preserve the
    upgrade storage layout. Compact pieces are the production source of truth.
    */

    // Network epoch delay between last proof of possession and next
    // randomness sampling for challenge generation.
    //
    // The purpose of this delay is to prevent SPs from biasing randomness by running forking attacks.
    // Given a small enough CHALLENGE_FINALITY an SP can run several trials of challenge sampling and
    // fork around samples that don't suit them, grinding the challenge randomness.
    // For the filecoin L1, a safe value is 150 using the same analysis setting 150 epochs between
    // PoRep precommit and PoRep provecommit phases.
    //
    // We keep this around for future portability to a variety of environments with different assumptions
    // behind their challenge randomness sampling methods.

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 private immutable CHALLENGE_FINALITY;
    uint256 private constant MAX_FINALITY = INACTIVITY_WINDOW / 2;
    // Block number when this implementation was deployed. Used as the activity baseline for legacy
    // datasets (dataSetLastProvenEpoch == 0) so they cannot be permissionlessly deleted immediately
    // after upgrade.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable LEGACY_ACTIVITY_EPOCH;

    uint256 deprecatedChallengeFinality;

    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329838769
    uint64 nextDataSetId;
    // Deprecated v1 piece storage retained for upgrade-layout compatibility.
    mapping(uint256 => mapping(uint256 => Cids.Cid)) pieceCids;
    mapping(uint256 => mapping(uint256 => uint256)) pieceLeafCounts;
    mapping(uint256 => mapping(uint256 => uint256)) sumTreeCounts;
    mapping(uint256 => uint256) nextPieceId;
    // The number of leaves (32 byte chunks) in the data set when tallying up all pieces.
    // This includes the leaves in pieces that have been added but are not yet eligible for proving.
    mapping(uint256 => uint256) dataSetLeafCount;
    // The epoch for which randomness is sampled for challenge generation while proving possession this proving period.
    mapping(uint256 => uint256) nextChallengeEpoch;
    // Each data set notifies a configurable listener to implement extensible applications managing data storage.
    mapping(uint256 => address) dataSetListener;
    // The first index that is not challenged in prove possession calls this proving period.
    // Updated to include the latest added leaves when starting the next proving period.
    mapping(uint256 => uint256) challengeRange;
    // Enqueued piece ids that must be removed before starting the next proving period
    mapping(uint256 => uint256[]) scheduledRemovals;
    // Legacy removal markers retained for upgrade compatibility. Compact pieces use a bit in PieceMetadata.
    mapping(uint256 dataSetId => mapping(uint256 slotIndex => uint256 bitmap)) scheduledRemovalsBitmap;
    // storage provider of data set is initialized upon creation to create message sender
    // storage provider has exclusive permission to add and remove pieces and delete the data set
    mapping(uint256 => address) storageProvider;
    mapping(uint256 => address) dataSetProposedStorageProvider;
    mapping(uint256 => uint256) dataSetLastProvenEpoch;

    // Packed fee status
    struct FeeStatus {
        uint96 currentFeePerTiB;
        uint96 nextFeePerTiB;
        uint64 transitionTime;
    }

    FeeStatus private feeStatus;

    // Used for announcing upgrades, packed into one slot
    struct PlannedUpgrade {
        // Address of the new implementation contract
        address nextImplementation;
        // Upgrade will not occur until at least this epoch
        uint96 afterEpoch;
    }

    // Pending upgrade announcement
    PlannedUpgrade public nextUpgrade;

    // FIL deposit collected at createDataSet and returned to whoever finalizes cleanup for that data set.
    mapping(uint256 => uint256) cleanupDeposit;
    // Former cleanupPieces gate anchor; only written by v3.4.0 deleteDataSet.
    mapping(uint256 => uint256) deprecatedCleanupModeEpoch;

    struct PieceV2 {
        bytes32 root;
        PieceMetadata metadata;
    }

    mapping(uint256 setId => PieceV2[] pieces) internal compactPieces;
    // Exclusive upper bound for data set IDs that use the legacy piece mappings.
    // Zero means the compact-storage cutover has not been initialized, so all data sets remain legacy.
    uint64 public legacyPieceStorageIdLimit;

    // Methods

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint64 _initializerVersion, uint256 _challengeFinality) {
        require(_challengeFinality < MAX_FINALITY / 10, ExcessiveChallengeDelay(_challengeFinality, MAX_FINALITY / 10));
        _disableInitializers();
        REINITIALIZER_VERSION = _initializerVersion;
        CHALLENGE_FINALITY = _challengeFinality;
        LEGACY_ACTIVITY_EPOCH = block.number;
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        nextDataSetId = 1; // Data sets start at 1
        legacyPieceStorageIdLimit = 1;
        feeStatus.nextFeePerTiB = PDPFees.DEFAULT_FEE_PER_TIB;
    }

    string public constant VERSION = "3.4.0";

    event ContractUpgraded(string version, address implementation);
    event UpgradeAnnounced(PlannedUpgrade plannedUpgrade);

    function migrate() external onlyProxy onlyOwner reinitializer(REINITIALIZER_VERSION) {
        if (legacyPieceStorageIdLimit == 0) {
            legacyPieceStorageIdLimit = nextDataSetId;
        }
        emit ContractUpgraded(VERSION, ERC1967Utils.getImplementation());
    }

    /// @notice Announce a planned upgrade
    /// @dev Can only be called by the contract owner
    /// @param nextImplementation Address of the new implementation contract
    /// @param delayEpochs Number of epochs from now before the upgrade may occur
    function announceUpgradePlan(address nextImplementation, uint96 delayEpochs) external {
        if (delayEpochs == 0) {
            delayEpochs = 1;
        }
        _announcePlannedUpgrade(nextImplementation, uint96(block.number) + delayEpochs);
    }

    /// @notice Announce a planned upgrade
    /// @dev Can only be called by the contract owner
    /// @param plannedUpgrade The planned upgrade details
    /// @custom:deprecated Use announceUpgradePlan instead
    function announcePlannedUpgrade(PlannedUpgrade calldata plannedUpgrade) external {
        uint96 minAfterEpoch = uint96(block.number + 1);
        _announcePlannedUpgrade(
            plannedUpgrade.nextImplementation,
            plannedUpgrade.afterEpoch < minAfterEpoch ? minAfterEpoch : plannedUpgrade.afterEpoch
        );
    }

    function _announcePlannedUpgrade(address nextImplementation, uint96 afterEpoch) internal onlyOwner {
        require(nextImplementation.code.length > 3000, InvalidImplementation(nextImplementation));
        nextUpgrade.nextImplementation = nextImplementation;
        nextUpgrade.afterEpoch = afterEpoch;
        emit UpgradeAnnounced(nextUpgrade);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // zero address already checked by ERC1967Utils._setImplementation
        require(newImplementation == nextUpgrade.nextImplementation);
        require(block.number >= nextUpgrade.afterEpoch);
        delete nextUpgrade;
    }

    function burnFee(uint256 amount) internal {
        require(msg.value >= amount, "Incorrect fee amount");
        bool success = FVMPay.burn(amount);
        require(success, "Burn failed");
    }

    // Handles fee payment for dataset creation: requires cleanup deposit in FIL. Stores the deposit for setId.
    // FVMPay.pay uses the SEND method (0) which transfers value without executing recipient code, so it cannot re-enter.
    function _handleFeesWithDeposit(uint256 setId) internal {
        uint256 deposit = PDPFees.cleanupDeposit();
        require(msg.value >= deposit, CleanupDepositRequired());
        cleanupDeposit[setId] = deposit;
        uint256 excess = msg.value - deposit;
        if (excess > 0) {
            require(FVMPay.pay(msg.sender, excess), TransferFailed());
        }
    }

    // Returns the current challenge finality value
    function getChallengeFinality() public view returns (uint256) {
        return CHALLENGE_FINALITY;
    }

    // Returns the next data set ID
    function getNextDataSetId() public view returns (uint64) {
        return nextDataSetId;
    }

    function _usesLegacyPieceStorage(uint256 setId) internal view returns (bool) {
        uint64 limit = legacyPieceStorageIdLimit;
        return limit == 0 || setId < limit;
    }

    function _pieceCount(uint256 setId, bool legacy) internal view returns (uint256) {
        return legacy ? nextPieceId[setId] : compactPieces[setId].length;
    }

    function _pieceLeafCount(uint256 setId, uint256 pieceId, bool legacy) internal view returns (uint256) {
        if (legacy) return pieceLeafCounts[setId][pieceId];
        if (pieceId >= compactPieces[setId].length) return 0;
        return compactPieces[setId][pieceId].metadata.leafCount();
    }

    function _pieceCidAt(uint256 setId, uint256 pieceId, bool legacy) internal view returns (Cids.Cid memory) {
        if (legacy) return pieceCids[setId][pieceId];
        if (pieceId >= compactPieces[setId].length) return Cids.Cid(new bytes(0));
        PieceV2 storage piece = compactPieces[setId][pieceId];
        if (piece.metadata.leafCount() == 0) return Cids.Cid(new bytes(0));
        return _pieceCid(piece.root, piece.metadata);
    }

    function _sumTreeValue(uint256 setId, uint256 pieceId, bool legacy) internal view returns (uint256) {
        return legacy ? sumTreeCounts[setId][pieceId] : compactPieces[setId][pieceId].metadata.sum();
    }

    function _proofRootAndHeight(uint256 setId, uint256 pieceId, bool legacy)
        internal
        view
        returns (bytes32 root, uint256 height)
    {
        if (!legacy) {
            PieceV2 storage piece = compactPieces[setId][pieceId];
            return (piece.root, piece.metadata.height() + 1);
        }

        bytes memory cidData = pieceCids[setId][pieceId].data;
        height = uint8(cidData[cidData.length - 33]) + 1;
        assembly ("memory-safe") {
            root := mload(add(cidData, mload(cidData)))
        }
    }

    // Returns false if the data set is 1) not yet created 2) fully deleted (cleanup complete)
    function dataSetExists(uint256 setId) internal view returns (bool) {
        return storageProvider[setId] != address(0);
    }

    // Returns false if the data set is 1) not yet created 2) deleted or in cleanup mode
    function dataSetLive(uint256 setId) public view returns (bool) {
        return dataSetExists(setId) && nextChallengeEpoch[setId] != CLEANUP_MODE_SENTINEL;
    }

    // Returns false if the data set is not live or if the piece id is 1) not yet created 2) deleted
    function pieceLive(uint256 setId, uint256 pieceId) public view returns (bool) {
        if (!dataSetLive(setId)) return false;
        bool legacy = _usesLegacyPieceStorage(setId);
        return pieceId < _pieceCount(setId, legacy) && _pieceLeafCount(setId, pieceId, legacy) > 0;
    }

    // Returns false if the piece is not live or if the piece id is not yet in challenge range
    function pieceChallengable(uint256 setId, uint256 pieceId) public view returns (bool) {
        bool legacy = _usesLegacyPieceStorage(setId);
        uint256 top = 256 - BitOps.clz(_pieceCount(setId, legacy));
        IPDPTypes.PieceIdAndOffset memory ret = findOnePieceId(setId, challengeRange[setId] - 1, top, legacy);
        require(
            ret.offset == _pieceLeafCount(setId, ret.pieceId, legacy) - 1,
            "challengeRange -1 should align with the very last leaf of a piece"
        );
        return pieceLive(setId, pieceId) && pieceId <= ret.pieceId;
    }

    // Returns the leaf count of a data set
    function getDataSetLeafCount(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), DataSetNotLive());
        return dataSetLeafCount[setId];
    }

    // Returns the next piece ID for a data set. Also valid during cleanup mode.
    function getNextPieceId(uint256 setId) public view returns (uint256) {
        require(dataSetExists(setId), DataSetNotFound());
        return _pieceCount(setId, _usesLegacyPieceStorage(setId));
    }

    // Returns the next challenge epoch for a data set. Returns zero after a processed deletion invalidates
    // the current challenge and until the next proving period; returns type(uint256).max during cleanup mode.
    function getNextChallengeEpoch(uint256 setId) public view returns (uint256) {
        require(dataSetExists(setId), DataSetNotFound());
        return nextChallengeEpoch[setId];
    }

    // Returns the listener address for a data set
    function getDataSetListener(uint256 setId) public view returns (address) {
        require(dataSetLive(setId), DataSetNotLive());
        return dataSetListener[setId];
    }

    // Returns the storage provider of a data set and the proposed storage provider if any
    function getDataSetStorageProvider(uint256 setId) public view returns (address, address) {
        require(dataSetLive(setId), DataSetNotLive());
        return (storageProvider[setId], dataSetProposedStorageProvider[setId]);
    }

    function getDataSetLastProvenEpoch(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), DataSetNotLive());
        return dataSetLastProvenEpoch[setId];
    }

    // Returns the piece CID for a given data set and piece ID
    function getPieceCid(uint256 setId, uint256 pieceId) public view returns (Cids.Cid memory) {
        require(dataSetLive(setId), DataSetNotLive());
        return _pieceCidAt(setId, pieceId, _usesLegacyPieceStorage(setId));
    }

    // Returns the piece leaf count for a given data set and piece ID
    function getPieceLeafCount(uint256 setId, uint256 pieceId) public view returns (uint256) {
        require(dataSetLive(setId), DataSetNotLive());
        return _pieceLeafCount(setId, pieceId, _usesLegacyPieceStorage(setId));
    }

    // Returns the index of the most recently added leaf that is challengeable in the current proving period
    function getChallengeRange(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), DataSetNotLive());
        return challengeRange[setId];
    }

    // Returns the piece ids scheduled for removal before the next proving period
    function getScheduledRemovals(uint256 setId) public view returns (uint256[] memory) {
        require(dataSetLive(setId), DataSetNotLive());
        uint256[] storage removals = scheduledRemovals[setId];
        uint256[] memory result = new uint256[](removals.length);
        for (uint256 i = 0; i < removals.length; i++) {
            result[i] = removals[i];
        }
        return result;
    }

    /**
     * @notice Returns the count of active pieces (non-zero leaf count) for a data set
     * @param setId The data set ID
     * @return activeCount The number of active pieces in the data set
     */
    function getActivePieceCount(uint256 setId) public view returns (uint256 activeCount) {
        require(dataSetLive(setId), DataSetNotLive());

        bool legacy = _usesLegacyPieceStorage(setId);
        uint256 maxPieceId = _pieceCount(setId, legacy);
        for (uint256 i = 0; i < maxPieceId; i++) {
            if (_pieceLeafCount(setId, i, legacy) > 0) {
                activeCount++;
            }
        }
    }

    /**
     * @notice Returns active pieces (non-zero leaf count) for a data set with pagination
     * @dev WARNING: This function has O(offset) gas complexity because it always iterates from
     * piece ID 0. For large data sets with high offsets, consider using getActivePiecesByCursor()
     * @param setId The data set ID
     * @param offset Starting index for pagination (0-based)
     * @param limit Maximum number of pieces to return
     * @return pieces Array of active piece CIDs
     * @return pieceIds Array of corresponding piece IDs
     * @return hasMore True if there are more pieces beyond this page
     */
    function getActivePieces(uint256 setId, uint256 offset, uint256 limit)
        public
        view
        returns (Cids.Cid[] memory pieces, uint256[] memory pieceIds, bool hasMore)
    {
        require(dataSetLive(setId), DataSetNotLive());
        require(limit > 0, "Limit must be greater than 0");

        // Single pass: collect data and check for more
        bool legacy = _usesLegacyPieceStorage(setId);
        uint256 maxPieceId = _pieceCount(setId, legacy);

        // Over-allocate arrays to limit size
        Cids.Cid[] memory tempPieces = new Cids.Cid[](limit);
        uint256[] memory tempPieceIds = new uint256[](limit);
        uint256 activeCount = 0;
        uint256 resultIndex = 0;

        for (uint256 i = 0; i < maxPieceId; i++) {
            if (_pieceLeafCount(setId, i, legacy) > 0) {
                if (activeCount >= offset && resultIndex < limit) {
                    tempPieces[resultIndex] = _pieceCidAt(setId, i, legacy);
                    tempPieceIds[resultIndex] = i;
                    resultIndex++;
                } else if (activeCount >= offset + limit) {
                    // Found at least one more active piece beyond our limit
                    hasMore = true;
                    break;
                }
                activeCount++;
            }
        }

        // Handle case where we found fewer items than limit
        if (resultIndex == 0) {
            // No items found
            return (new Cids.Cid[](0), new uint256[](0), false);
        } else if (resultIndex < limit) {
            // Found fewer items than limit - need to resize arrays
            pieces = tempPieces;
            pieceIds = tempPieceIds;
            assembly ("memory-safe") {
                mstore(pieces, resultIndex)
                mstore(pieceIds, resultIndex)
            }
        } else {
            // Found exactly limit items - use temp arrays directly
            pieces = tempPieces;
            pieceIds = tempPieceIds;
        }
    }

    /**
     * @notice Returns active pieces using cursor-based pagination for O(limit) gas complexity
     * @dev This function is more gas-efficient than getActivePieces() for large data sets because
     * it starts iteration from startPieceId instead of always from 0. Use this for paginating
     * through large data sets.
     * @param setId The data set ID
     * @param startPieceId The piece ID to start from (use 0 for first page, then last returned pieceId + 1)
     * @param limit Maximum number of pieces to return
     * @return pieces Array of active piece CIDs
     * @return pieceIds Array of corresponding piece IDs
     * @return hasMore True if there are more pieces beyond this page
     */
    function getActivePiecesByCursor(uint256 setId, uint256 startPieceId, uint256 limit)
        public
        view
        returns (Cids.Cid[] memory pieces, uint256[] memory pieceIds, bool hasMore)
    {
        require(dataSetLive(setId), DataSetNotLive());
        require(limit > 0, "Limit must be greater than 0");

        bool legacy = _usesLegacyPieceStorage(setId);
        uint256 maxPieceId = _pieceCount(setId, legacy);
        // If startPieceId is beyond all pieces, return empty
        if (startPieceId >= maxPieceId) {
            return (new Cids.Cid[](0), new uint256[](0), false);
        }

        // Over-allocate arrays to limit size
        Cids.Cid[] memory tempPieces = new Cids.Cid[](limit);
        uint256[] memory tempPieceIds = new uint256[](limit);
        uint256 resultIndex = 0;

        // Start from startPieceId and collect up to limit
        for (uint256 i = startPieceId; i < maxPieceId && resultIndex < limit; i++) {
            if (_pieceLeafCount(setId, i, legacy) > 0) {
                tempPieces[resultIndex] = _pieceCidAt(setId, i, legacy);
                tempPieceIds[resultIndex] = i;
                resultIndex++;
            }
        }

        // Check if there are more active pieces after last one we found
        if (resultIndex > 0) {
            uint256 lastFound = tempPieceIds[resultIndex - 1];
            for (uint256 i = lastFound + 1; i < maxPieceId; i++) {
                if (_pieceLeafCount(setId, i, legacy) > 0) {
                    hasMore = true;
                    break;
                }
            }
        }

        // Handle case where we found fewer items than limit
        if (resultIndex == 0) {
            return (new Cids.Cid[](0), new uint256[](0), false);
        } else if (resultIndex < limit) {
            pieces = tempPieces;
            pieceIds = tempPieceIds;
            assembly ("memory-safe") {
                mstore(pieces, resultIndex)
                mstore(pieceIds, resultIndex)
            }
        } else {
            pieces = tempPieces;
            pieceIds = tempPieceIds;
        }
    }

    /**
     * @notice Finds piece IDs matching a given piece CID, with cursor-based pagination
     * @param setId The data set ID
     * @param pieceCid The piece CID to search for
     * @param startPieceId Piece ID to start scanning from (0 for first call)
     * @param limit Maximum number of matching piece IDs to return
     * @return pieceIds Array of matching piece IDs (up to limit)
     */
    function findPieceIdsByCid(uint256 setId, Cids.Cid calldata pieceCid, uint256 startPieceId, uint256 limit)
        public
        view
        returns (uint256[] memory pieceIds)
    {
        require(dataSetLive(setId), DataSetNotLive());
        require(limit > 0, "Limit must be greater than 0");

        if (_usesLegacyPieceStorage(setId)) {
            return _findLegacyPieceIdsByCid(setId, pieceCid, startPieceId, limit);
        }
        return _findCompactPieceIdsByCid(setId, pieceCid, startPieceId, limit);
    }

    function _findLegacyPieceIdsByCid(uint256 setId, Cids.Cid calldata pieceCid, uint256 startPieceId, uint256 limit)
        internal
        view
        returns (uint256[] memory pieceIds)
    {
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 targetHash = keccak256(pieceCid.data);
        uint256 maxPieceId = _pieceCount(setId, true);
        pieceIds = new uint256[](limit);
        uint256 count;
        for (uint256 i = startPieceId; i < maxPieceId && count < limit; i++) {
            if (_pieceLeafCount(setId, i, true) > 0 && keccak256(pieceCids[setId][i].data) == targetHash) {
                pieceIds[count++] = i;
            }
        }
        assembly ("memory-safe") {
            mstore(pieceIds, count)
        }
    }

    function _findCompactPieceIdsByCid(uint256 setId, Cids.Cid calldata pieceCid, uint256 startPieceId, uint256 limit)
        internal
        view
        returns (uint256[] memory pieceIds)
    {
        (uint256 padding, uint8 height, bytes32 root) = Cids.validateCommPv2(pieceCid);
        uint256 maxPieceId = _pieceCount(setId, false);
        pieceIds = new uint256[](limit);
        uint256 count;
        for (uint256 i = startPieceId; i < maxPieceId && count < limit; i++) {
            PieceV2 storage piece = compactPieces[setId][i];
            if (
                _pieceLeafCount(setId, i, false) > 0 && piece.root == root && piece.metadata.padding() == padding
                    && piece.metadata.height() == height
            ) {
                pieceIds[count++] = i;
            }
        }
        assembly ("memory-safe") {
            mstore(pieceIds, count)
        }
    }

    // storage provider proposes new storage provider.  If the storage provider proposes themself delete any outstanding proposed storage provider
    function proposeDataSetStorageProvider(uint256 setId, address newStorageProvider) public {
        require(dataSetLive(setId), DataSetNotLive());
        address currentStorageProvider = storageProvider[setId];
        require(
            currentStorageProvider == msg.sender, "Only the current storage provider can propose a new storage provider"
        );
        if (currentStorageProvider == newStorageProvider) {
            // If the storage provider proposes themself delete any outstanding proposed storage provider
            delete dataSetProposedStorageProvider[setId];
        } else {
            dataSetProposedStorageProvider[setId] = newStorageProvider;
        }
    }

    function claimDataSetStorageProvider(uint256 setId, bytes calldata extraData) public {
        require(dataSetLive(setId), DataSetNotLive());
        require(
            dataSetProposedStorageProvider[setId] == msg.sender,
            "Only the proposed storage provider can claim storage provider role"
        );
        address oldStorageProvider = storageProvider[setId];
        storageProvider[setId] = msg.sender;
        delete dataSetProposedStorageProvider[setId];
        emit StorageProviderChanged(setId, oldStorageProvider, msg.sender);
        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).storageProviderChanged(setId, oldStorageProvider, msg.sender, extraData);
        }
    }

    // Internal helper to create a new data set and initialize its state.
    // Returns the newly created data set ID.
    function _createDataSet(address listenerAddr, bytes memory extraData) internal returns (uint256) {
        uint256 setId = nextDataSetId++;
        dataSetLeafCount[setId] = 0;
        storageProvider[setId] = msg.sender;
        dataSetListener[setId] = listenerAddr;
        dataSetLastProvenEpoch[setId] = block.number;

        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).dataSetCreated(setId, msg.sender, extraData);
        }
        emit DataSetCreated(setId, msg.sender);

        return setId;
    }

    // Creates a new empty data set with no pieces. Pieces can be added later via addPieces().
    // This is the simpler alternative to creating and adding pieces atomically via addPieces(NEW_DATA_SET_SENTINEL, ...).
    //
    // Parameters:
    //   - listenerAddr: Address of PDPListener contract to receive callbacks (can be address(0) for no listener)
    //   - extraData: Arbitrary bytes passed to listener's dataSetCreated callback
    //   - msg.value: Must include cleanup deposit (PDPFees.cleanupDeposit()). Excess is refunded.
    //
    // Returns: The newly created data set ID
    //
    // Only the storage provider (msg.sender) can call this function.
    function createDataSet(address listenerAddr, bytes calldata extraData) public payable returns (uint256) {
        uint256 setId = _createDataSet(listenerAddr, extraData);
        _handleFeesWithDeposit(setId);
        return setId;
    }

    // True within INACTIVITY_WINDOW blocks of the last proving activity. Past that the data set
    // is abandoned and deleteDataSet/cleanupPieces become permissionless.
    // Legacy data sets (lastProvenEpoch == 0) use the implementation deployment block as baseline.
    function _withinActivityWindow(uint256 setId) internal view returns (bool) {
        uint256 lastActivity = dataSetLastProvenEpoch[setId];
        if (lastActivity == NO_PROVEN_EPOCH) {
            lastActivity = LEGACY_ACTIVITY_EPOCH;
        }
        return block.number <= lastActivity + INACTIVITY_WINDOW;
    }

    // Removes a data set. Normally called by the storage provider; permissionless after INACTIVITY_WINDOW
    // blocks of SP inactivity (measured from dataSetLastProvenEpoch).
    //
    // After this call the data set is no longer live. If pieces remain, cleanup mode is entered and
    // cleanupPieces must be called to finish storage teardown and collect the cleanup deposit.
    // For zero-piece data sets, cleanup is finalized immediately and the deposit is paid to msg.sender.
    function deleteDataSet(uint256 setId, bytes calldata extraData) public {
        address sp = storageProvider[setId];
        require(sp != address(0), DataSetNotLive());
        require(nextChallengeEpoch[setId] != CLEANUP_MODE_SENTINEL, DataSetAlreadyInCleanup());

        if (_withinActivityWindow(setId)) {
            require(msg.sender == sp, OnlyStorageProvider());
        }

        uint256 deletedLeafCount = dataSetLeafCount[setId];
        dataSetLeafCount[setId] = 0;

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).dataSetDeleted(setId, deletedLeafCount, extraData);
        }
        emit DataSetDeleted(setId, deletedLeafCount);

        bool legacy = _usesLegacyPieceStorage(setId);
        if (_pieceCount(setId, legacy) == 0) {
            // Zero-piece data set: finalize cleanup immediately and pay deposit to caller.
            _finalizeCleanup(setId, legacy);
        } else {
            // Pieces remain: enter cleanup mode. storageProvider and dataSetLastProvenEpoch are kept
            // so cleanupPieces can apply the same permission gate; the latter cannot advance here
            // since provePossession, nextProvingPeriod and addPieces all revert on a deleted set.
            nextChallengeEpoch[setId] = CLEANUP_MODE_SENTINEL;
        }
    }

    // Releases storage for a deleted data set piece-by-piece. This is available after deleteDataSet
    // has placed the data set in cleanup mode (nextChallengeEpoch == CLEANUP_MODE_SENTINEL), or for
    // legacy data sets deleted before cleanup mode existed (storageProvider == 0 && nextPieceId > 0).
    //
    // The caller gate is identical to deleteDataSet: SP-exclusive within INACTIVITY_WINDOW blocks of
    // the last proving activity, permissionless after, so an abandoned data set can be deleted and
    // cleaned up back-to-back by one caller. Historical deleted legacy data sets are permissionless.
    //
    // On the final call that clears all pieces, all remaining data set state is also cleared and
    // the cleanup deposit is transferred to msg.sender. Returns true when cleanup is complete.
    function cleanupPieces(uint256 setId, uint256 maxPieces) external returns (bool done) {
        require(maxPieces > 0, MaxPiecesMustBePositive());

        bool legacy = _usesLegacyPieceStorage(setId);
        bool isCleanupMode = nextChallengeEpoch[setId] == CLEANUP_MODE_SENTINEL;
        bool isHistoricalLegacyDelete = legacy && storageProvider[setId] == address(0) && nextPieceId[setId] > 0;
        require(isCleanupMode || isHistoricalLegacyDelete, DataSetNotInCleanupMode());

        if (isCleanupMode && _withinActivityWindow(setId)) {
            require(msg.sender == storageProvider[setId], OnlyStorageProvider());
        }

        uint256 pieceCount = _pieceCount(setId, legacy);
        uint256 toClean = pieceCount < maxPieces ? pieceCount : maxPieces;
        if (legacy) {
            for (uint256 i = 0; i < toClean; i++) {
                uint256 pieceId = pieceCount - 1 - i;
                delete pieceCids[setId][pieceId];
                delete pieceLeafCounts[setId][pieceId];
                delete sumTreeCounts[setId][pieceId];
            }
            nextPieceId[setId] = pieceCount - toClean;
        } else {
            PieceV2[] storage pieces = compactPieces[setId];
            for (uint256 i = 0; i < toClean; i++) {
                pieces.pop();
            }
        }

        if (_pieceCount(setId, legacy) == 0) {
            _finalizeCleanup(setId, legacy);
            done = true;
        }
    }

    // Clears all remaining singleton state for a data set and transfers the cleanup deposit to msg.sender.
    // Must only be called when the selected piece representation's count is zero.
    function _finalizeCleanup(uint256 setId, bool legacy) internal {
        // Pending legacy removals may still have markers in the compatibility bitmap.
        uint256[] storage removals = scheduledRemovals[setId];
        if (legacy) {
            for (uint256 i = 0; i < removals.length; i++) {
                delete scheduledRemovalsBitmap[setId][removals[i] >> 8];
            }
        }
        delete scheduledRemovals[setId];

        delete dataSetListener[setId];
        delete dataSetProposedStorageProvider[setId];
        delete challengeRange[setId];
        delete storageProvider[setId];
        delete dataSetLastProvenEpoch[setId];
        delete nextChallengeEpoch[setId];
        // Clears residue from v3.4.0-era deletes.
        delete deprecatedCleanupModeEpoch[setId];

        uint256 deposit = cleanupDeposit[setId];
        delete cleanupDeposit[setId];

        if (deposit > 0) {
            require(FVMPay.pay(msg.sender, deposit), DepositTransferFailed());
        }
    }

    // Appends pieces to a data set. Optionally creates a new data set if setId == 0.
    // These pieces won't be challenged until the next proving period is started by calling nextProvingPeriod.
    //
    // Two modes of operation:
    // 1. Add to existing data set:
    //    - setId: ID of the existing data set
    //    - listenerAddr: must be address(0)
    //    - extraData: arbitrary bytes passed to the listener's piecesAdded callback
    //    - msg.value: must be 0 (no fee required)
    //    - Returns: first piece ID added
    //
    // 2. Create new data set and add pieces (atomic operation):
    //    - setId: must be NEW_DATA_SET_SENTINEL (0)
    //    - listenerAddr: listener contract address (required, cannot be address(0))
    //    - pieceData: array of pieces to add (can be empty to create empty data set)
    //    - extraData: abi.encode(bytes createPayload, bytes addPayload) where:
    //      - createPayload: passed to listener's dataSetCreated callback
    //      - addPayload: passed to listener's piecesAdded callback (if pieces added)
    //    - msg.value: must include cleanup deposit (PDPFees.cleanupDeposit()), excess is refunded
    //    - Returns: the newly created data set ID
    //
    // Only the storage provider can call this function.
    function addPieces(uint256 setId, address listenerAddr, Cids.Cid[] calldata pieceData, bytes calldata extraData)
        public
        payable
        returns (uint256)
    {
        if (setId == NEW_DATA_SET_SENTINEL) {
            (bytes memory createPayload, bytes memory addPayload) = abi.decode(extraData, (bytes, bytes));

            require(listenerAddr != address(0), "listener required for new dataset");

            uint256 newSetId = _createDataSet(listenerAddr, createPayload);

            // Add pieces to the newly created data set (if any)
            if (pieceData.length > 0) {
                _addPiecesToDataSet(newSetId, pieceData, addPayload);
            }

            _handleFeesWithDeposit(newSetId);
            return newSetId;
        } else {
            // Adding to an existing set; no fee should be sent and listenerAddr must be zero
            require(listenerAddr == address(0), "listener must be zero for existing dataset");
            require(msg.value == 0, "no fee on add to existing dataset");

            require(dataSetLive(setId), DataSetNotLive());
            require(storageProvider[setId] == msg.sender, "Only the storage provider can add pieces");

            return _addPiecesToDataSet(setId, pieceData, extraData);
        }
    }

    // Internal function to add pieces to a data set and handle events/listeners
    function _addPiecesToDataSet(uint256 setId, Cids.Cid[] calldata pieceData, bytes memory extraData)
        internal
        returns (uint256 firstAdded)
    {
        uint256 nPieces = pieceData.length;
        require(nPieces > 0, "Must add at least one piece");

        bool legacy = _usesLegacyPieceStorage(setId);
        firstAdded = _pieceCount(setId, legacy);
        uint256 newLeafCount = dataSetLeafCount[setId];
        uint256[] memory pieceIds = new uint256[](nPieces);
        Cids.Cid[] memory pieceCidsAdded = new Cids.Cid[](nPieces);

        for (uint256 i = 0; i < nPieces; i++) {
            uint256 leafCount = addOnePiece(setId, i, pieceData[i], legacy);
            if (!legacy && newLeafCount > SUM_TREE_MAX - leafCount) revert PieceMetadataOverflow();
            newLeafCount += leafCount;
            pieceIds[i] = firstAdded + i;
            pieceCidsAdded[i] = pieceData[i];
        }

        dataSetLeafCount[setId] = newLeafCount;

        emit PiecesAdded(setId, pieceIds, pieceCidsAdded);

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).piecesAdded(setId, firstAdded, pieceData, extraData);
        }
    }

    error IndexedError(uint256 idx, string msg);
    error CleanupDepositRequired();
    error DataSetNotFound();
    error DataSetNotLive();
    error DataSetAlreadyInCleanup();
    error MaxPiecesMustBePositive();
    error EmptyRemovalBatch();
    error DataSetNotInCleanupMode();
    error DepositTransferFailed();
    error TransferFailed();
    error OnlyStorageProvider();
    error InvalidPieceDeletionBatch();
    error PendingPieceDeletions(uint256 count);
    error NoPiecesToProve();
    error InsufficientChallengeDelay(uint256 epochs, uint256 minDelay);
    error ExcessiveChallengeDelay(uint256 epochs, uint256 maxDelay);
    error InvalidImplementation(address implementation);

    function _pieceCid(bytes32 root, PieceMetadata metadata) internal pure returns (Cids.Cid memory) {
        return Cids.CommPv2FromDigest(metadata.padding(), uint8(metadata.height()), root);
    }

    function addOnePiece(uint256 setId, uint256 callIdx, Cids.Cid calldata piece, bool legacy)
        internal
        returns (uint256 leafCount)
    {
        (uint256 padding, uint8 height, bytes32 root) = Cids.validateCommPv2(piece);
        if (Cids.isPaddingExcessive(padding, height)) {
            revert IndexedError(callIdx, "Padding is too large");
        }
        if (height > MAX_PIECE_SIZE_LOG2) {
            revert IndexedError(callIdx, "Piece size must be less than 2^50");
        }

        leafCount = Cids.leafCount(padding, height);
        if (!legacy && leafCount > LEAF_COUNT_MAX) revert PieceMetadataOverflow();

        uint256 pieceId = _pieceCount(setId, legacy);
        uint256 sum = sumTreeAdd(setId, leafCount, pieceId, legacy);
        if (legacy) {
            pieceCids[setId][pieceId] = piece;
            pieceLeafCounts[setId][pieceId] = leafCount;
            nextPieceId[setId] = pieceId + 1;
        } else {
            compactPieces[setId].push(
                PieceV2({root: root, metadata: PieceMetadataLibrary.pack(padding, height, leafCount, sum)})
            );
        }
    }

    // schedulePieceDeletions schedules deletion of a batch of pieces from a data set before the next proving period.
    // It must be called by the storage provider.
    function schedulePieceDeletions(uint256 setId, uint256[] calldata pieceIds, bytes calldata extraData) public {
        require(dataSetLive(setId), DataSetNotLive());
        require(storageProvider[setId] == msg.sender, "Only the storage provider can schedule removal of pieces");
        require(pieceIds.length > 0, EmptyRemovalBatch());
        require(
            pieceIds.length + scheduledRemovals[setId].length <= MAX_ENQUEUED_REMOVALS,
            "Too many removals wait for next proving period to schedule"
        );

        bool legacy = _usesLegacyPieceStorage(setId);
        uint256 pieceCount = _pieceCount(setId, legacy);
        for (uint256 i = 0; i < pieceIds.length; i++) {
            uint256 pieceId = pieceIds[i];
            require(pieceId < pieceCount, "Can only schedule removal of existing pieces");
            require(_pieceLeafCount(setId, pieceId, legacy) > 0, "Can only schedule removal of live pieces");

            if (legacy) {
                uint256 slotIndex = pieceId >> 8;
                uint256 bitMask = 1 << (pieceId & 255);
                require(
                    (scheduledRemovalsBitmap[setId][slotIndex] & bitMask) == 0, "Piece ID already scheduled for removal"
                );
                scheduledRemovalsBitmap[setId][slotIndex] |= bitMask;
            } else {
                PieceV2 storage piece = compactPieces[setId][pieceId];
                require(!piece.metadata.removalQueued(), "Piece ID already scheduled for removal");
                piece.metadata = piece.metadata.withRemovalQueued();
            }

            // Add to scheduled removals array
            scheduledRemovals[setId].push(pieceId);
        }

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).piecesScheduledRemove(setId, pieceIds, extraData);
        }

        for (uint256 start = 0; start < pieceIds.length; start += PIECE_ID_EVENT_BATCH_SIZE) {
            uint256 end = start + PIECE_ID_EVENT_BATCH_SIZE;
            if (end > pieceIds.length) {
                end = pieceIds.length;
            }
            emit PiecesScheduledForRemoval(setId, pieceIds[start:end]);
        }
    }

    // Executes deletions from the end of the data set's scheduled-removal queue and invalidates its challenge.
    function processPieceDeletions(uint256 setId, uint256 removalCount) external {
        require(dataSetLive(setId), DataSetNotLive());
        require(storageProvider[setId] == msg.sender, OnlyStorageProvider());

        require(removalCount > 0, EmptyRemovalBatch());

        uint256[] storage removals = scheduledRemovals[setId];
        uint256 queueLength = removals.length;
        require(removalCount <= queueLength, InvalidPieceDeletionBatch());

        uint256[] memory pieceIds = new uint256[](removalCount);
        uint256 suffixStart = queueLength - removalCount;
        for (uint256 i = 0; i < removalCount; i++) {
            pieceIds[i] = removals[suffixStart + i];
        }

        bool legacy = _usesLegacyPieceStorage(setId);
        removePieces(setId, pieceIds);

        _popProcessedRemovals(setId, pieceIds, legacy);
        nextChallengeEpoch[setId] = NO_CHALLENGE_SCHEDULED;

        _emitPiecesRemoved(setId, pieceIds);
    }

    function _popProcessedRemovals(uint256 setId, uint256[] memory pieceIds, bool legacy) private {
        uint256[] storage removals = scheduledRemovals[setId];
        uint256 removalCount = pieceIds.length;

        if (legacy) {
            uint256 currentSlotIndex = pieceIds[removalCount - 1] >> 8;
            uint256 bitsToClear;
            for (uint256 i = removalCount; i > 0; i--) {
                uint256 pieceId = pieceIds[i - 1];
                uint256 slotIndex = pieceId >> 8;
                uint256 bitPosition = pieceId & 255;

                if (slotIndex != currentSlotIndex) {
                    scheduledRemovalsBitmap[setId][currentSlotIndex] &= ~bitsToClear;
                    currentSlotIndex = slotIndex;
                    bitsToClear = 0;
                }

                bitsToClear |= 1 << bitPosition;
                removals.pop();
            }
            scheduledRemovalsBitmap[setId][currentSlotIndex] &= ~bitsToClear;
            return;
        }

        for (uint256 i = removalCount; i > 0; i--) {
            removals.pop();
        }
    }

    function _emitPiecesRemoved(uint256 setId, uint256[] memory pieceIds) private {
        if (pieceIds.length <= PIECE_ID_EVENT_BATCH_SIZE) {
            emit PiecesRemoved(setId, pieceIds);
            return;
        }

        for (uint256 start = 0; start < pieceIds.length; start += PIECE_ID_EVENT_BATCH_SIZE) {
            uint256 chunkLength = PIECE_ID_EVENT_BATCH_SIZE;
            if (start + chunkLength > pieceIds.length) {
                chunkLength = pieceIds.length - start;
            }

            uint256[] memory chunk = new uint256[](chunkLength);
            for (uint256 i = 0; i < chunkLength; i++) {
                chunk[i] = pieceIds[start + i];
            }
            emit PiecesRemoved(setId, chunk);
        }
    }

    // Verifies and records that the provider proved possession of the
    // data set Merkle pieces at some epoch. The challenge seed is determined
    // by the epoch of the previous proof of possession.
    function provePossession(uint256 setId, IPDPTypes.Proof[] calldata proofs) public payable {
        uint256 nProofs = proofs.length;
        require(msg.sender == storageProvider[setId], "Only the storage provider can prove possession");
        require(nProofs > 0, "empty proof");
        {
            uint256 challengeEpoch = nextChallengeEpoch[setId];
            require(block.number >= challengeEpoch, "premature proof");
            require(challengeEpoch != NO_CHALLENGE_SCHEDULED, "no challenge scheduled");
        }

        IPDPTypes.PieceIdAndOffset[] memory challenges = new IPDPTypes.PieceIdAndOffset[](proofs.length);

        uint256 seed = drawChallengeSeed(setId);
        {
            uint256 leafCount = challengeRange[setId];
            bool legacy = _usesLegacyPieceStorage(setId);
            uint256 sumTreeTop = 256 - BitOps.clz(_pieceCount(setId, legacy));
            for (uint64 i = 0; i < nProofs; i++) {
                // Hash (SHA3) the seed,  data set id, and proof index to create challenge.
                // Note -- there is a slight deviation here from the uniform distribution.
                // Some leaves are challenged with probability p and some have probability p + deviation.
                // This deviation is bounded by leafCount / 2^256 given a 256 bit hash.
                // Deviation grows with data set leaf count.
                // Assuming a 1000EiB = 1 ZiB network size ~ 2^70 bytes of data or 2^65 leaves
                // This deviation is bounded by 2^65 / 2^256 = 2^-191 which is negligible.
                //   If modifying this code to use a hash function with smaller output size
                //   this deviation will increase and caution is advised.
                // To remove this deviation we could use the standard solution of rejection sampling
                //   This is complicated and slightly more costly at one more hash on average for maximally misaligned data sets
                //   and comes at no practical benefit given how small the deviation is.
                bytes memory payload = abi.encodePacked(seed, setId, i);
                uint256 challengeIdx = uint256(keccak256(payload)) % leafCount;

                // Find the piece that has this leaf, and the offset of the leaf within that piece.
                challenges[i] = _findAndVerifyProof(setId, proofs[i], challengeIdx, sumTreeTop, legacy);
            }
        }

        // Note: We don't want to include gas spent on the listener call in the fee calculation
        // to only account for proof verification fees and avoid gamability by getting the listener
        // to do extraneous work just to inflate the gas fee.
        //
        // (add 32 bytes to the `callDataSize` to also account for the `setId` calldata param)
        uint256 refund = calculateAndBurnProofFee(setId);
        dataSetLastProvenEpoch[setId] = block.number;

        {
            address listenerAddr = dataSetListener[setId];
            if (listenerAddr != address(0)) {
                PDPListener(listenerAddr).possessionProven(setId, dataSetLeafCount[setId], seed, proofs.length);
            }
        }

        emit PossessionProven(setId, challenges);

        // Return the overpayment. FVMPay.pay uses SEND (method 0) which transfers value without executing recipient code and cannot re-enter.
        // If the transfer fails, the entire operation reverts.
        if (refund > 0) {
            bool success = FVMPay.pay(msg.sender, refund);
            require(success, "Transfer failed.");
        }
    }

    function _findAndVerifyProof(
        uint256 setId,
        IPDPTypes.Proof calldata proof,
        uint256 challengeIdx,
        uint256 sumTreeTop,
        bool legacy
    ) internal view returns (IPDPTypes.PieceIdAndOffset memory challenge) {
        challenge = findOnePieceId(setId, challengeIdx, sumTreeTop, legacy);
        (bytes32 root, uint256 height) = _proofRootAndHeight(setId, challenge.pieceId, legacy);
        require(MerkleVerify.verify(proof.proof, root, proof.leaf, challenge.offset, height), "proof did not verify");
    }

    function calculateProofFee(uint256 setId) public view returns (uint256) {
        // proofSize is the number of bytes that will be charged for the proof.
        // challengeRange is a leaf count (32-byte chunks), so multiply by 32 to get bytes.
        uint256 proofSize = 32 * challengeRange[setId];
        return calculateProofFeeForSize(proofSize);
    }

    function calculateProofFeeForSize(uint256 proofSize) public view returns (uint256) {
        require(proofSize > 0, "failed to validate: proof size must be greater than 0");
        return PDPFees.calculateProofFee(proofSize, _currentFeePerTiB());
    }

    function calculateAndBurnProofFee(uint256 setId) internal returns (uint256 refund) {
        uint256 proofSize = 32 * challengeRange[setId];
        uint256 proofFee = calculateProofFeeForSize(proofSize);

        burnFee(proofFee);
        emit ProofFeePaid(setId, proofFee);

        return msg.value - proofFee; // burnFee asserts that proofFee <= msg.value;
    }

    function _currentFeePerTiB() internal view returns (uint96) {
        return block.timestamp >= feeStatus.transitionTime ? feeStatus.nextFeePerTiB : feeStatus.currentFeePerTiB;
    }

    function FIL_CLEANUP_DEPOSIT() external pure returns (uint256) {
        return PDPFees.cleanupDeposit();
    }

    // Public getters for packed fee status
    function feePerTiB() public view returns (uint96) {
        return _currentFeePerTiB();
    }

    function proposedFeePerTiB() public view returns (uint96) {
        return feeStatus.nextFeePerTiB;
    }

    function feeEffectiveTime() public view returns (uint64) {
        return feeStatus.transitionTime;
    }

    function getRandomness(uint256 epoch) public view returns (uint256) {
        // Call the precompile
        return FVMRandom.getBeaconRandomness(epoch);
    }

    function drawChallengeSeed(uint256 setId) internal view returns (uint256) {
        return getRandomness(nextChallengeEpoch[setId]);
    }

    // Start the next proving period.
    //
    // This method updates the collection of provable pieces in the data set by updating the challenge range to
    // include leaves added in the last proving period. Scheduled deletions must be processed before this method
    // is called.
    //
    // Additionally this method forces sampling of a new challenge.  It enforces that the new
    // challenge epoch is at least `CHALLENGE_FINALITY` epochs in the future.
    //
    // Note that this method can be called at any time but the pdpListener will likely consider it
    // a "fault" or other penalizeable behavior to call this method before calling provePossesion.
    function nextProvingPeriod(uint256 setId, uint256 challengeEpoch, bytes calldata extraData) public {
        require(msg.sender == storageProvider[setId], "only the storage provider can move to next proving period");
        uint256 pendingDeletionCount = scheduledRemovals[setId].length;
        require(pendingDeletionCount == 0, PendingPieceDeletions(pendingDeletionCount));
        // challengeRange stays nonzero while an active proving lifecycle is being drained, which permits
        // one zero-leaf call to close it out after the final piece has been removed.
        require(dataSetLeafCount[setId] > 0 || (dataSetLive(setId) && challengeRange[setId] > 0), NoPiecesToProve());

        if (dataSetLastProvenEpoch[setId] == NO_PROVEN_EPOCH) {
            dataSetLastProvenEpoch[setId] = block.number;
        }

        // Bring added pieces into proving set
        challengeRange[setId] = dataSetLeafCount[setId];
        unchecked {
            uint256 delayEpochs = challengeEpoch - block.number;
            require(delayEpochs >= CHALLENGE_FINALITY, InsufficientChallengeDelay(delayEpochs, CHALLENGE_FINALITY));
            require(delayEpochs <= MAX_FINALITY, ExcessiveChallengeDelay(delayEpochs, MAX_FINALITY));
        }
        nextChallengeEpoch[setId] = challengeEpoch;

        // Clear next challenge epoch if the set is now empty.
        // It will be re-set after new data is added and nextProvingPeriod is called.
        if (dataSetLeafCount[setId] == 0) {
            emit DataSetEmpty(setId);
            dataSetLastProvenEpoch[setId] = block.number;
            nextChallengeEpoch[setId] = NO_CHALLENGE_SCHEDULED;
        }

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr)
                .nextProvingPeriod(setId, nextChallengeEpoch[setId], dataSetLeafCount[setId], extraData);
        }
        emit NextProvingPeriod(setId, challengeEpoch, dataSetLeafCount[setId]);
    }

    // removes pieces from a data set's state.
    function removePieces(uint256 setId, uint256[] memory pieceIds) internal {
        require(dataSetLive(setId), DataSetNotLive());
        bool legacy = _usesLegacyPieceStorage(setId);
        uint256 totalDelta = 0;
        for (uint256 i = 0; i < pieceIds.length; i++) {
            totalDelta += removeOnePiece(setId, pieceIds[i], legacy);
        }
        dataSetLeafCount[setId] -= totalDelta;
    }

    // removeOnePiece clears a piece's live data while retaining its updated Fenwick sum and returns
    // the number of leafs by which to reduce the total data set leaf count.
    function removeOnePiece(uint256 setId, uint256 pieceId, bool legacy) internal returns (uint256) {
        uint256 delta = _pieceLeafCount(setId, pieceId, legacy);
        sumTreeRemove(setId, pieceId, delta, legacy);
        if (legacy) {
            delete pieceLeafCounts[setId][pieceId];
            delete pieceCids[setId][pieceId];
        } else {
            compactPieces[setId][pieceId].root = bytes32(0);
        }
        return delta;
    }

    /* Sum tree functions */
    /*
    A sumtree is a variant of a Fenwick or binary indexed tree.  It is a binary
    tree where each node is the sum of its children. It is designed to support
    efficient query and update operations on a base array of integers. Here
    the base array is the pieces leaf count array.  Asymptotically the sum tree
    has logarithmic search and update functions.  Each slot of the sum tree is
    logically a node in a binary tree.

    The node’s height from the leaf depth is defined as -1 + the ruler function
    (https://oeis.org/A001511 [0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,...]) applied to
    the slot’s index + 1, i.e. the number of trailing 0s in the binary representation
    of the index + 1.  Each slot in the sum tree array contains the sum of a range
    of the base array.  The size of this range is defined by the height assigned
    to this slot in the binary tree structure of the sum tree, i.e. the value of
    the ruler function applied to the slot’s index.  The range for height d and
    current index j is [j + 1 - 2^d : j] inclusive.  For example if the node’s
    height is 0 its value is set to the base array’s value at the same index and
    if the node’s height is 3 then its value is set to the sum of the last 2^3 = 8
    values of the base array. The reason to do things with recursive partial sums
    is to accommodate O(log len(base array)) updates for add and remove operations
    on the base array.
    */

    // Perform sumtree addition
    //
    function sumTreeAdd(uint256 setId, uint256 count, uint256 pieceId, bool legacy) internal returns (uint256 sum) {
        uint256 h = heightFromIndex(pieceId);

        sum = count;
        // Sum BaseArray[j - 2^i] for i in [0, h)
        for (uint256 i = 0; i < h; i++) {
            uint256 priorIndex = pieceId - (1 << i);
            sum += _sumTreeValue(setId, priorIndex, legacy);
        }
        if (legacy) {
            sumTreeCounts[setId][pieceId] = sum;
        } else if (sum > SUM_TREE_MAX) {
            revert PieceMetadataOverflow();
        }
    }

    // Perform sumtree removal
    //
    function sumTreeRemove(uint256 setId, uint256 index, uint256 delta, bool legacy) internal {
        uint256 pieceCount = _pieceCount(setId, legacy);
        uint256 removedIndex = index;
        uint256 top = uint256(256 - BitOps.clz(pieceCount));
        uint256 h = uint256(heightFromIndex(index));

        // Deletion traversal either terminates at
        // 1) the top of the tree or
        // 2) the highest node right of the removal index
        while (h <= top && index < pieceCount) {
            uint256 sum = _sumTreeValue(setId, index, legacy) - delta;
            if (legacy) {
                sumTreeCounts[setId][index] = sum;
            } else {
                PieceV2 storage piece = compactPieces[setId][index];
                piece.metadata =
                    index == removedIndex ? piece.metadata.withSum(sum).clearExceptSum() : piece.metadata.withSum(sum);
            }
            index += 1 << h;
            h = heightFromIndex(index);
        }
    }

    // Perform sumtree find
    function findOnePieceId(uint256 setId, uint256 leafIndex, uint256 top, bool legacy)
        internal
        view
        returns (IPDPTypes.PieceIdAndOffset memory)
    {
        require(leafIndex < dataSetLeafCount[setId], "Leaf index out of bounds");
        uint256 pieceCount = _pieceCount(setId, legacy);
        uint256 searchPtr = (1 << top) - 1;
        uint256 acc = 0;

        // Binary search until we find the index of the sumtree leaf covering the index range
        uint256 candidate;
        for (uint256 h = top; h > 0; h--) {
            // Search has taken us past the end of the sumtree, so the only option is to go left.
            if (searchPtr >= pieceCount) {
                searchPtr -= 1 << (h - 1);
                continue;
            }

            uint256 sum = _sumTreeValue(setId, searchPtr, legacy);
            candidate = acc + sum;
            // Go right
            if (candidate <= leafIndex) {
                acc += sum;
                searchPtr += 1 << (h - 1);
            } else {
                // Go left
                searchPtr -= 1 << (h - 1);
            }
        }
        candidate = acc + _sumTreeValue(setId, searchPtr, legacy);
        if (candidate <= leafIndex) {
            // Choose right
            return IPDPTypes.PieceIdAndOffset(searchPtr + 1, leafIndex - candidate);
        }
        // Choose left
        return IPDPTypes.PieceIdAndOffset(searchPtr, leafIndex - acc);
    }

    // findPieceIds is a batched version of findOnePieceId
    function findPieceIds(uint256 setId, uint256[] calldata leafIndexs)
        public
        view
        returns (IPDPTypes.PieceIdAndOffset[] memory)
    {
        // The top of the sumtree is the largest power of 2 less than the number of pieces
        bool legacy = _usesLegacyPieceStorage(setId);
        uint256 top = 256 - BitOps.clz(_pieceCount(setId, legacy));
        IPDPTypes.PieceIdAndOffset[] memory result = new IPDPTypes.PieceIdAndOffset[](leafIndexs.length);
        for (uint256 i = 0; i < leafIndexs.length; i++) {
            result[i] = findOnePieceId(setId, leafIndexs[i], top, legacy);
        }
        return result;
    }

    // Return height of sumtree node at given index
    // Calculated by taking the trailing zeros of 1 plus the index
    function heightFromIndex(uint256 index) internal pure returns (uint256) {
        return BitOps.ctz(index + 1);
    }

    /// @notice Proposes a new proof fee with 7-day delay
    /// @param newFeePerTiB The new fee per TiB in AttoFIL
    function updateProofFee(uint256 newFeePerTiB) external onlyOwner {
        // Auto-commit any pending update that has reached its transition time
        if (block.timestamp >= feeStatus.transitionTime) {
            feeStatus.currentFeePerTiB = feeStatus.nextFeePerTiB;
        }
        feeStatus.nextFeePerTiB = uint96(newFeePerTiB);
        feeStatus.transitionTime = uint64(block.timestamp + 7 days);
        emit FeeUpdateProposed(feeStatus.currentFeePerTiB, newFeePerTiB, feeStatus.transitionTime);
    }
}
