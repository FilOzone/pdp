// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {BitOps} from "./BitOps.sol";
import {Cids} from "./Cids.sol";
import {MerkleVerify} from "./Proofs.sol";
import {PDPFees} from "./Fees.sol";
import {ERC1967Utils} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {FVMPay} from "fvm-solidity/FVMPay.sol";
import {FVMRandom} from "fvm-solidity/FVMRandom.sol";
import {IPDPTypes} from "./interfaces/IPDPTypes.sol";

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

contract PDPVerifier is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Constants
    uint256 public constant MAX_PIECE_SIZE_LOG2 = 50;
    uint256 public constant MAX_ENQUEUED_REMOVALS = 2000;
    uint256 public constant NO_CHALLENGE_SCHEDULED = 0;
    uint256 public constant NO_PROVEN_EPOCH = 0;

    // Events
    event DataSetCreated(uint256 indexed setId, address indexed storageProvider);
    event StorageProviderChanged(
        uint256 indexed setId, address indexed oldStorageProvider, address indexed newStorageProvider
    );
    event DataSetDeleted(uint256 indexed setId, uint256 deletedLeafCount);
    event DataSetEmpty(uint256 indexed setId);

    event PiecesAdded(uint256 indexed setId, uint256[] pieceIds, Cids.Cid[] pieceCids);
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

    To implement this logical structure in the solidity data model we have
    arrays tracking the singleton fields and two dimensional arrays
    tracking linear data set data.  The first index is the data set id
    and the second index if any is the index of the data in the array.

    Invariant: pieceCids.length == pieceLeafCount.length == sumTreeCounts.length
    */

    // Network epoch delay between last proof of possession and next
    // randomness sampling for challenge generation.
    //
    // The purpose of this delay is to prevent SPs from biasing randomness by running forking attacks.
    // Given a small enough challengeFinality an SP can run several trials of challenge sampling and
    // fork around samples that don't suit them, grinding the challenge randomness.
    // For the filecoin L1, a safe value is 150 using the same analysis setting 150 epochs between
    // PoRep precommit and PoRep provecommit phases.
    //
    // We keep this around for future portability to a variety of environments with different assumptions
    // behind their challenge randomness sampling methods.
    uint256 challengeFinality;

    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329838769
    uint64 nextDataSetId;
    // The CID of each piece. Pieces and all their associated data can be appended and removed but not modified.
    mapping(uint256 => mapping(uint256 => Cids.Cid)) pieceCids;
    // The leaf count of each piece
    mapping(uint256 => mapping(uint256 => uint256)) pieceLeafCounts;
    // The sum tree array for finding the piece id of a given leaf index.
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
    // Enqueued piece ids for removal when starting the next proving period
    mapping(uint256 => uint256[]) scheduledRemovals;
    // Track which pieces are scheduled for removal with a bitmap
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

    // Methods

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _challengeFinality) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        challengeFinality = _challengeFinality;
        nextDataSetId = 1; // Data sets start at 1
        feeStatus.nextFeePerTiB = PDPFees.DEFAULT_FEE_PER_TIB;
    }

    string public constant VERSION = "3.0.0";

    event ContractUpgraded(string version, address implementation);

    function migrate() external onlyOwner reinitializer(2) {
        emit ContractUpgraded(VERSION, ERC1967Utils.getImplementation());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function burnFee(uint256 amount) internal {
        require(msg.value >= amount, "Incorrect fee amount");
        bool success = FVMPay.burn(amount);
        require(success, "Burn failed");
    }

    // Validates msg.value meets sybil fee requirement and burns the fee.
    // Returns the sybil fee amount for later refund calculation.
    function _validateAndBurnSybilFee() internal returns (uint256 sybilFee) {
        sybilFee = PDPFees.sybilFee();
        require(msg.value >= sybilFee, "sybil fee not met");
        burnFee(sybilFee);
    }

    // Refunds any amount sent over the sybil fee back to msg.sender.
    // Must be called after all state changes to avoid re-entrancy issues.
    function _refundExcessSybilFee(uint256 sybilFee) internal {
        if (msg.value > sybilFee) {
            (bool success,) = msg.sender.call{value: msg.value - sybilFee}("");
            require(success, "Transfer failed.");
        }
    }

    // Returns the current challenge finality value
    function getChallengeFinality() public view returns (uint256) {
        return challengeFinality;
    }

    // Returns the next data set ID
    function getNextDataSetId() public view returns (uint64) {
        return nextDataSetId;
    }

    // Returns false if the data set is 1) not yet created 2) deleted
    function dataSetLive(uint256 setId) public view returns (bool) {
        return setId < nextDataSetId && storageProvider[setId] != address(0);
    }

    // Returns false if the data set is not live or if the piece id is 1) not yet created 2) deleted
    function pieceLive(uint256 setId, uint256 pieceId) public view returns (bool) {
        return dataSetLive(setId) && pieceId < nextPieceId[setId] && pieceLeafCounts[setId][pieceId] > 0;
    }

    // Returns false if the piece is not live or if the piece id is not yet in challenge range
    function pieceChallengable(uint256 setId, uint256 pieceId) public view returns (bool) {
        uint256 top = 256 - BitOps.clz(nextPieceId[setId]);
        IPDPTypes.PieceIdAndOffset memory ret = findOnePieceId(setId, challengeRange[setId] - 1, top);
        require(
            ret.offset == pieceLeafCounts[setId][ret.pieceId] - 1,
            "challengeRange -1 should align with the very last leaf of a piece"
        );
        return pieceLive(setId, pieceId) && pieceId <= ret.pieceId;
    }

    // Returns the leaf count of a data set
    function getDataSetLeafCount(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), "Data set not live");
        return dataSetLeafCount[setId];
    }

    // Returns the next piece ID for a data set
    function getNextPieceId(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), "Data set not live");
        return nextPieceId[setId];
    }

    // Returns the next challenge epoch for a data set
    function getNextChallengeEpoch(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), "Data set not live");
        return nextChallengeEpoch[setId];
    }

    // Returns the listener address for a data set
    function getDataSetListener(uint256 setId) public view returns (address) {
        require(dataSetLive(setId), "Data set not live");
        return dataSetListener[setId];
    }

    // Returns the storage provider of a data set and the proposed storage provider if any
    function getDataSetStorageProvider(uint256 setId) public view returns (address, address) {
        require(dataSetLive(setId), "Data set not live");
        return (storageProvider[setId], dataSetProposedStorageProvider[setId]);
    }

    function getDataSetLastProvenEpoch(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), "Data set not live");
        return dataSetLastProvenEpoch[setId];
    }

    // Returns the piece CID for a given data set and piece ID
    function getPieceCid(uint256 setId, uint256 pieceId) public view returns (Cids.Cid memory) {
        require(dataSetLive(setId), "Data set not live");
        return pieceCids[setId][pieceId];
    }

    // Returns the piece leaf count for a given data set and piece ID
    function getPieceLeafCount(uint256 setId, uint256 pieceId) public view returns (uint256) {
        require(dataSetLive(setId), "Data set not live");
        return pieceLeafCounts[setId][pieceId];
    }

    // Returns the index of the most recently added leaf that is challengeable in the current proving period
    function getChallengeRange(uint256 setId) public view returns (uint256) {
        require(dataSetLive(setId), "Data set not live");
        return challengeRange[setId];
    }

    // Returns the piece ids of the pieces scheduled for removal at the start of the next proving period
    function getScheduledRemovals(uint256 setId) public view returns (uint256[] memory) {
        require(dataSetLive(setId), "Data set not live");
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
        require(dataSetLive(setId), "Data set not live");

        uint256 maxPieceId = nextPieceId[setId];
        for (uint256 i = 0; i < maxPieceId; i++) {
            if (pieceLeafCounts[setId][i] > 0) {
                activeCount++;
            }
        }
    }

    /**
     * @notice Returns active pieces (non-zero leaf count) for a data set with pagination
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
        require(dataSetLive(setId), "Data set not live");
        require(limit > 0, "Limit must be greater than 0");

        // Single pass: collect data and check for more
        uint256 maxPieceId = nextPieceId[setId];

        // Over-allocate arrays to limit size
        Cids.Cid[] memory tempPieces = new Cids.Cid[](limit);
        uint256[] memory tempPieceIds = new uint256[](limit);

        uint256 activeCount = 0;
        uint256 resultIndex = 0;

        for (uint256 i = 0; i < maxPieceId; i++) {
            if (pieceLeafCounts[setId][i] > 0) {
                if (activeCount >= offset && resultIndex < limit) {
                    tempPieces[resultIndex] = pieceCids[setId][i];
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
            pieces = new Cids.Cid[](resultIndex);
            pieceIds = new uint256[](resultIndex);

            for (uint256 i = 0; i < resultIndex; i++) {
                pieces[i] = tempPieces[i];
                pieceIds[i] = tempPieceIds[i];
            }
        } else {
            // Found exactly limit items - use temp arrays directly
            pieces = tempPieces;
            pieceIds = tempPieceIds;
        }
    }

    // storage provider proposes new storage provider.  If the storage provider proposes themself delete any outstanding proposed storage provider
    function proposeDataSetStorageProvider(uint256 setId, address newStorageProvider) public {
        require(dataSetLive(setId), "Data set not live");
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
        require(dataSetLive(setId), "Data set not live");
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
        nextChallengeEpoch[setId] = NO_CHALLENGE_SCHEDULED; // initialized on first call to NextProvingPeriod
        storageProvider[setId] = msg.sender;
        dataSetListener[setId] = listenerAddr;
        dataSetLastProvenEpoch[setId] = NO_PROVEN_EPOCH;

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
    //   - msg.value: Must include sybil fee (PDPFees.sybilFee()), excess is refunded
    //
    // Returns: The newly created data set ID
    //
    // Only the storage provider (msg.sender) can call this function.
    function createDataSet(address listenerAddr, bytes calldata extraData) public payable returns (uint256) {
        uint256 sybilFee = _validateAndBurnSybilFee();

        uint256 setId = _createDataSet(listenerAddr, extraData);

        _refundExcessSybilFee(sybilFee);
        return setId;
    }

    // Removes a data set. Must be called by the storage provider.
    function deleteDataSet(uint256 setId, bytes calldata extraData) public {
        if (setId >= nextDataSetId) {
            revert("data set id out of bounds");
        }

        require(storageProvider[setId] == msg.sender, "Only the storage provider can delete data sets");
        uint256 deletedLeafCount = dataSetLeafCount[setId];
        dataSetLeafCount[setId] = 0;
        storageProvider[setId] = address(0);
        nextChallengeEpoch[setId] = 0;
        dataSetLastProvenEpoch[setId] = NO_PROVEN_EPOCH;

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).dataSetDeleted(setId, deletedLeafCount, extraData);
        }
        emit DataSetDeleted(setId, deletedLeafCount);
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
    //    - msg.value: must include sybil fee (PDPFees.sybilFee()), excess is refunded
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

            uint256 sybilFee = _validateAndBurnSybilFee();

            require(listenerAddr != address(0), "listener required for new dataset");
            uint256 newSetId = _createDataSet(listenerAddr, createPayload);

            // Add pieces to the newly created data set (if any)
            if (pieceData.length > 0) {
                _addPiecesToDataSet(newSetId, pieceData, addPayload);
            }

            _refundExcessSybilFee(sybilFee);
            return newSetId;
        } else {
            // Adding to an existing set; no fee should be sent and listenerAddr must be zero
            require(listenerAddr == address(0), "listener must be zero for existing dataset");
            require(msg.value == 0, "no fee on add to existing dataset");

            require(dataSetLive(setId), "Data set not live");
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

        firstAdded = nextPieceId[setId];
        uint256[] memory pieceIds = new uint256[](nPieces);
        Cids.Cid[] memory pieceCidsAdded = new Cids.Cid[](nPieces);

        for (uint256 i = 0; i < nPieces; i++) {
            addOnePiece(setId, i, pieceData[i]);
            pieceIds[i] = firstAdded + i;
            pieceCidsAdded[i] = pieceData[i];
        }

        emit PiecesAdded(setId, pieceIds, pieceCidsAdded);

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).piecesAdded(setId, firstAdded, pieceData, extraData);
        }
    }

    error IndexedError(uint256 idx, string msg);

    function addOnePiece(uint256 setId, uint256 callIdx, Cids.Cid calldata piece) internal returns (uint256) {
        (uint256 padding, uint8 height,) = Cids.validateCommPv2(piece);
        if (Cids.isPaddingExcessive(padding, height)) {
            revert IndexedError(callIdx, "Padding is too large");
        }
        if (height > MAX_PIECE_SIZE_LOG2) {
            revert IndexedError(callIdx, "Piece size must be less than 2^50");
        }

        uint256 leafCount = Cids.leafCount(padding, height);
        uint256 pieceId = nextPieceId[setId]++;

        sumTreeAdd(setId, leafCount, pieceId);
        pieceCids[setId][pieceId] = piece;
        pieceLeafCounts[setId][pieceId] = leafCount;
        dataSetLeafCount[setId] += leafCount;
        return pieceId;
    }

    // schedulePieceDeletions schedules deletion of a batch of pieces from a data set for the start of the next
    // proving period. It must be called by the storage provider.
    function schedulePieceDeletions(uint256 setId, uint256[] calldata pieceIds, bytes calldata extraData) public {
        require(dataSetLive(setId), "Data set not live");
        require(storageProvider[setId] == msg.sender, "Only the storage provider can schedule removal of pieces");
        require(
            pieceIds.length + scheduledRemovals[setId].length <= MAX_ENQUEUED_REMOVALS,
            "Too many removals wait for next proving period to schedule"
        );

        for (uint256 i = 0; i < pieceIds.length; i++) {
            uint256 pieceId = pieceIds[i];
            require(pieceId < nextPieceId[setId], "Can only schedule removal of existing pieces");
            require(pieceLeafCounts[setId][pieceId] > 0, "Can only schedule removal of live pieces");

            // Check for duplicates using bitmap
            uint256 slotIndex = pieceId >> 8;
            uint256 bitPosition = pieceId & 255;
            uint256 bitMask = 1 << bitPosition;

            require(
                (scheduledRemovalsBitmap[setId][slotIndex] & bitMask) == 0, "Piece ID already scheduled for removal"
            );

            // Mark as scheduled for removal in bitmap
            scheduledRemovalsBitmap[setId][slotIndex] |= bitMask;

            // Add to scheduled removals array
            scheduledRemovals[setId].push(pieceId);
        }

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).piecesScheduledRemove(setId, pieceIds, extraData);
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
            uint256 sumTreeTop = 256 - BitOps.clz(nextPieceId[setId]);
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
                challenges[i] = findOnePieceId(setId, challengeIdx, sumTreeTop);
                Cids.Cid memory pieceCid = getPieceCid(setId, challenges[i].pieceId);
                bytes32 pieceHash = Cids.digestFromCid(pieceCid);
                uint8 pieceHeight = Cids.heightFromCid(pieceCid) + 1; // because MerkleVerify.verify assumes that base layer is 1
                bool ok =
                    MerkleVerify.verify(proofs[i].proof, pieceHash, proofs[i].leaf, challenges[i].offset, pieceHeight);
                require(ok, "proof did not verify");
            }
        }

        // Note: We don't want to include gas spent on the listener call in the fee calculation
        // to only account for proof verification fees and avoid gamability by getting the listener
        // to do extraneous work just to inflate the gas fee.
        //
        // (add 32 bytes to the `callDataSize` to also account for the `setId` calldata param)
        uint256 refund = calculateAndBurnProofFee(setId);

        {
            address listenerAddr = dataSetListener[setId];
            if (listenerAddr != address(0)) {
                PDPListener(listenerAddr).possessionProven(setId, dataSetLeafCount[setId], seed, proofs.length);
            }
        }

        dataSetLastProvenEpoch[setId] = block.number;
        emit PossessionProven(setId, challenges);

        // Return the overpayment after doing everything else to avoid re-entrancy issues (all state has been updated by this point). If this
        // call fails, the entire operation reverts.
        if (refund > 0) {
            bool success = FVMPay.pay(msg.sender, refund);
            require(success, "Transfer failed.");
        }
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

    // Roll over to the next proving period
    //
    // This method updates the collection of provable pieces in the data set by
    // 1. Actually removing the pieces that have been scheduled for removal
    // 2. Updating the challenge range to now include leaves added in the last proving period
    // So after this method is called pieces scheduled for removal are no longer eligible for challenging
    // and can be deleted.  And pieces added in the last proving period must be available for challenging.
    //
    // Additionally this method forces sampling of a new challenge.  It enforces that the new
    // challenge epoch is at least `challengeFinality` epochs in the future.
    //
    // Note that this method can be called at any time but the pdpListener will likely consider it
    // a "fault" or other penalizeable behavior to call this method before calling provePossesion.
    function nextProvingPeriod(uint256 setId, uint256 challengeEpoch, bytes calldata extraData) public {
        require(msg.sender == storageProvider[setId], "only the storage provider can move to next proving period");
        require(dataSetLeafCount[setId] > 0, "can only start proving once leaves are added");

        if (dataSetLastProvenEpoch[setId] == NO_PROVEN_EPOCH) {
            dataSetLastProvenEpoch[setId] = block.number;
        }

        // Take removed pieces out of proving set
        uint256[] storage removals = scheduledRemovals[setId];
        uint256 nRemovals = removals.length;
        if (nRemovals > 0) {
            uint256[] memory removalsToProcess = new uint256[](nRemovals);

            // Copy removals to a memory array so we can clear the storage one
            for (uint256 i = 0; i < nRemovals; i++) {
                uint256 pieceId = removals[i];
                removalsToProcess[i] = pieceId;

                // Clear the bitmap, as bitmap and array are in sync and we are going to delete everything from the array,
                // we can remove by 256bit chunk
                uint256 slotIndex = pieceId >> 8;
                delete scheduledRemovalsBitmap[setId][slotIndex];
            }

            delete scheduledRemovals[setId];

            removePieces(setId, removalsToProcess);
            emit PiecesRemoved(setId, removalsToProcess);
        }

        // Bring added pieces into proving set
        challengeRange[setId] = dataSetLeafCount[setId];
        if (challengeEpoch < block.number + challengeFinality) {
            revert("challenge epoch must be at least challengeFinality epochs in the future");
        }
        nextChallengeEpoch[setId] = challengeEpoch;

        // Clear next challenge epoch if the set is now empty.
        // It will be re-set after new data is added and nextProvingPeriod is called.
        if (dataSetLeafCount[setId] == 0) {
            emit DataSetEmpty(setId);
            dataSetLastProvenEpoch[setId] = NO_PROVEN_EPOCH;
            nextChallengeEpoch[setId] = NO_CHALLENGE_SCHEDULED;
        }

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).nextProvingPeriod(
                setId, nextChallengeEpoch[setId], dataSetLeafCount[setId], extraData
            );
        }
        emit NextProvingPeriod(setId, challengeEpoch, dataSetLeafCount[setId]);
    }

    // removes pieces from a data set's state.
    function removePieces(uint256 setId, uint256[] memory pieceIds) internal {
        require(dataSetLive(setId), "Data set not live");
        uint256 totalDelta = 0;
        for (uint256 i = 0; i < pieceIds.length; i++) {
            totalDelta += removeOnePiece(setId, pieceIds[i]);
        }
        dataSetLeafCount[setId] -= totalDelta;
    }

    // removeOnePiece removes a piece's array entries from the data sets state and returns
    // the number of leafs by which to reduce the total data set leaf count.
    function removeOnePiece(uint256 setId, uint256 pieceId) internal returns (uint256) {
        uint256 delta = pieceLeafCounts[setId][pieceId];
        sumTreeRemove(setId, pieceId, delta);
        delete pieceLeafCounts[setId][pieceId];
        delete pieceCids[setId][pieceId];
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
    function sumTreeAdd(uint256 setId, uint256 count, uint256 pieceId) internal {
        uint256 index = pieceId;
        uint256 h = heightFromIndex(index);

        uint256 sum = count;
        // Sum BaseArray[j - 2^i] for i in [0, h)
        for (uint256 i = 0; i < h; i++) {
            uint256 j = index - (1 << i);
            sum += sumTreeCounts[setId][j];
        }
        sumTreeCounts[setId][pieceId] = sum;
    }

    // Perform sumtree removal
    //
    function sumTreeRemove(uint256 setId, uint256 index, uint256 delta) internal {
        uint256 top = uint256(256 - BitOps.clz(nextPieceId[setId]));
        uint256 h = uint256(heightFromIndex(index));

        // Deletion traversal either terminates at
        // 1) the top of the tree or
        // 2) the highest node right of the removal index
        while (h <= top && index < nextPieceId[setId]) {
            sumTreeCounts[setId][index] -= delta;
            index += 1 << h;
            h = heightFromIndex(index);
        }
    }

    // Perform sumtree find
    function findOnePieceId(uint256 setId, uint256 leafIndex, uint256 top)
        internal
        view
        returns (IPDPTypes.PieceIdAndOffset memory)
    {
        require(leafIndex < dataSetLeafCount[setId], "Leaf index out of bounds");
        uint256 searchPtr = (1 << top) - 1;
        uint256 acc = 0;

        // Binary search until we find the index of the sumtree leaf covering the index range
        uint256 candidate;
        for (uint256 h = top; h > 0; h--) {
            // Search has taken us past the end of the sumtree
            // Only option is to go left
            if (searchPtr >= nextPieceId[setId]) {
                searchPtr -= 1 << (h - 1);
                continue;
            }

            candidate = acc + sumTreeCounts[setId][searchPtr];
            // Go right
            if (candidate <= leafIndex) {
                acc += sumTreeCounts[setId][searchPtr];
                searchPtr += 1 << (h - 1);
            } else {
                // Go left
                searchPtr -= 1 << (h - 1);
            }
        }
        candidate = acc + sumTreeCounts[setId][searchPtr];
        if (candidate <= leafIndex) {
            // Choose right
            return IPDPTypes.PieceIdAndOffset(searchPtr + 1, leafIndex - candidate);
        } // Choose left
        return IPDPTypes.PieceIdAndOffset(searchPtr, leafIndex - acc);
    }

    // findPieceIds is a batched version of findOnePieceId
    function findPieceIds(uint256 setId, uint256[] calldata leafIndexs)
        public
        view
        returns (IPDPTypes.PieceIdAndOffset[] memory)
    {
        // The top of the sumtree is the largest power of 2 less than the number of pieces
        uint256 top = 256 - BitOps.clz(nextPieceId[setId]);
        IPDPTypes.PieceIdAndOffset[] memory result = new IPDPTypes.PieceIdAndOffset[](leafIndexs.length);
        for (uint256 i = 0; i < leafIndexs.length; i++) {
            result[i] = findOnePieceId(setId, leafIndexs[i], top);
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
