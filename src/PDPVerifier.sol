// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

import {BitOps} from "./BitOps.sol";
import {Cids} from "./Cids.sol";
import {MerkleVerify} from "./Proofs.sol";
import {PDPFees} from "./Fees.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IPDPTypes} from "./interfaces/IPDPTypes.sol";
import {IPDPEvents} from "./interfaces/IPDPEvents.sol";

/// @title PDPListener
/// @notice Interface for PDP Service applications managing data storage.
/// @dev This interface exists to provide an extensible hook for applications to use the PDP verification contract
/// to implement data storage applications.
interface PDPListener {
    function dataSetCreated(uint256 dataSetId, address creator, bytes calldata extraData) external;
    function dataSetDeleted(uint256 dataSetId, uint256 deletedLeafCount, bytes calldata extraData) external;
    function piecesAdded(uint256 dataSetId, uint256 firstAdded, Cids.Cid[] memory pieceData, bytes calldata extraData) external;
    function piecesScheduledRemove(uint256 dataSetId, uint256[] memory pieceIds, bytes calldata extraData) external;
    // Note: extraData not included as proving messages conceptually always originate from the SP
    function possessionProven(uint256 dataSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount) external;
    function nextProvingPeriod(uint256 dataSetId, uint256 challengeEpoch, uint256 leafCount, bytes calldata extraData) external;
    /// @notice Called when data set storage provider is changed in PDPVerifier.
    function storageProviderChanged(uint256 dataSetId, address oldStorageProvider, address newStorageProvider, bytes calldata extraData) external;
}

contract PDPVerifier is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Constants
    address public constant BURN_ACTOR = 0xff00000000000000000000000000000000000063;
    uint256 public constant LEAF_SIZE = 32;
    uint256 public constant MAX_PIECE_SIZE_LOG2 = 50;
    uint256 public constant MAX_ENQUEUED_REMOVALS = 2000;
    address public constant RANDOMNESS_PRECOMPILE = 0xfE00000000000000000000000000000000000006;
    uint256 public constant EXTRA_DATA_MAX_SIZE = 2048;
    uint256 public constant SECONDS_IN_DAY = 86400;
    IPyth public constant PYTH = IPyth(0xA2aa501b19aff244D90cc15a4Cf739D2725B5729);

    // FIL/USD price feed query ID on the Pyth network
    bytes32 public constant FIL_USD_PRICE_FEED_ID = 0x150ac9b959aee0051e4091f0ef5216d941f590e1c5e7f91cf7635b5c11628c0e;
    uint256 public constant NO_CHALLENGE_SCHEDULED = 0;
    uint256 public constant NO_PROVEN_EPOCH = 0;


    // Events
    event DataSetCreated(uint256 indexed setId, address indexed storageProvider);
    event StorageProviderChanged(uint256 indexed setId, address indexed oldStorageProvider, address indexed newStorageProvider);
    event DataSetDeleted(uint256 indexed setId, uint256 deletedLeafCount);
    event DataSetEmpty(uint256 indexed setId);

    event PiecesAdded(uint256 indexed setId, uint256[] pieceIds);
    event PiecesRemoved(uint256 indexed setId, uint256[] pieceIds);

    event ProofFeePaid(uint256 indexed setId, uint256 fee, uint64 price, int32 expo);


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
    // storage provider of data set is initialized upon creation to create message sender
    // storage provider has exclusive permission to add and remove pieces and delete the data set
    mapping(uint256 => address) storageProvider;
    mapping(uint256 => address) dataSetProposedStorageProvider;
    mapping(uint256 => uint256) dataSetLastProvenEpoch;

    // Methods

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
     _disableInitializers();
    }

    function initialize(uint256 _challengeFinality) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        challengeFinality = _challengeFinality;
    }

    string public constant VERSION = "2.0.0";
    event ContractUpgraded(string version, address implementation);

    function migrate() external onlyOwner reinitializer(2) {
        emit ContractUpgraded(VERSION, ERC1967Utils.getImplementation());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function burnFee(uint256 amount) internal {
        require(msg.value >= amount, "Incorrect fee amount");
        (bool success, ) = BURN_ACTOR.call{value: amount}("");
        require(success, "Burn failed");
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
        IPDPTypes.PieceIdAndOffset memory ret = findOnePieceId(setId, challengeRange[setId]-1, top);
        require(ret.offset == pieceLeafCounts[setId][ret.pieceId] - 1, "challengeRange -1 should align with the very last leaf of a piece");
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
     * @return rawSizes Array of raw sizes for each piece (in bytes)
     * @return hasMore True if there are more pieces beyond this page
     */
    function getActivePieces(
        uint256 setId,
        uint256 offset,
        uint256 limit
    ) public view returns (
        Cids.Cid[] memory pieces,
        uint256[] memory pieceIds,
        uint256[] memory rawSizes,
        bool hasMore
    ) {
        require(dataSetLive(setId), "Data set not live");
        require(limit > 0, "Limit must be greater than 0");

        // Single pass: collect data and check for more
        uint256 maxPieceId = nextPieceId[setId];

        // Over-allocate arrays to limit size
        Cids.Cid[] memory tempPieces = new Cids.Cid[](limit);
        uint256[] memory tempPieceIds = new uint256[](limit);
        uint256[] memory tempRawSizes = new uint256[](limit);

        uint256 activeCount = 0;
        uint256 resultIndex = 0;

        for (uint256 i = 0; i < maxPieceId; i++) {
            if (pieceLeafCounts[setId][i] > 0) {
                if (activeCount >= offset && resultIndex < limit) {
                    tempPieces[resultIndex] = pieceCids[setId][i];
                    tempPieceIds[resultIndex] = i;
                    tempRawSizes[resultIndex] = pieceLeafCounts[setId][i] * 32;
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
            return (new Cids.Cid[](0), new uint256[](0), new uint256[](0), false);
        } else if (resultIndex < limit) {
            // Found fewer items than limit - need to resize arrays
            pieces = new Cids.Cid[](resultIndex);
            pieceIds = new uint256[](resultIndex);
            rawSizes = new uint256[](resultIndex);

            for (uint256 i = 0; i < resultIndex; i++) {
                pieces[i] = tempPieces[i];
                pieceIds[i] = tempPieceIds[i];
                rawSizes[i] = tempRawSizes[i];
            }
        } else {
            // Found exactly limit items - use temp arrays directly
            pieces = tempPieces;
            pieceIds = tempPieceIds;
            rawSizes = tempRawSizes;
        }
    }

    // storage provider proposes new storage provider.  If the storage provider proposes themself delete any outstanding proposed storage provider
    function proposeDataSetStorageProvider(uint256 setId, address newStorageProvider) public {
        require(dataSetLive(setId), "Data set not live");
        address currentStorageProvider = storageProvider[setId];
        require(currentStorageProvider == msg.sender, "Only the current storage provider can propose a new storage provider");
        if (currentStorageProvider == newStorageProvider) {
            // If the storage provider proposes themself delete any outstanding proposed storage provider
            delete dataSetProposedStorageProvider[setId];
        } else {
            dataSetProposedStorageProvider[setId] = newStorageProvider;
        }
    }

    function claimDataSetStorageProvider(uint256 setId, bytes calldata extraData) public {
        require(dataSetLive(setId), "Data set not live");
        require(dataSetProposedStorageProvider[setId] == msg.sender, "Only the proposed storage provider can claim storage provider role");
        address oldStorageProvider = storageProvider[setId];
        storageProvider[setId] = msg.sender;
        delete dataSetProposedStorageProvider[setId];
        emit StorageProviderChanged(setId, oldStorageProvider, msg.sender);
        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).storageProviderChanged(setId, oldStorageProvider, msg.sender, extraData);
        }
    }

    // A data set is created empty, with no pieces. Creation yields a data set ID
    // for referring to the data set later.
    // Sender of create message is storage provider.
    function createDataSet(address listenerAddr, bytes calldata extraData) public payable returns (uint256) {
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        uint256 sybilFee = PDPFees.sybilFee();
        require(msg.value >= sybilFee, "sybil fee not met");
        burnFee(sybilFee);

        uint256 setId = nextDataSetId++;
        dataSetLeafCount[setId] = 0;
        nextChallengeEpoch[setId] = NO_CHALLENGE_SCHEDULED;  // Initialized on first call to NextProvingPeriod
        storageProvider[setId] = msg.sender;
        dataSetListener[setId] = listenerAddr;
        dataSetLastProvenEpoch[setId] = NO_PROVEN_EPOCH;

        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).dataSetCreated(setId, msg.sender, extraData);
        }
        emit DataSetCreated(setId, msg.sender);

        // Return the at the end to avoid any possible re-entrency issues.
        if (msg.value > sybilFee) {
            (bool success, ) = msg.sender.call{value: msg.value - sybilFee}("");
            require(success, "Transfer failed.");
        }
        return setId;
    }

    // Removes a data set. Must be called by the storage provider.
    function deleteDataSet(uint256 setId, bytes calldata extraData) public {
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
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

    // Appends new pieces to the collection managed by a data set.
    // These pieces won't be challenged until the next proving period is
    // started by calling nextProvingPeriod.
    function addPieces(uint256 setId, Cids.Cid[] calldata pieceData, bytes calldata extraData) public returns (uint256) {
        uint256 nPieces = pieceData.length;
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        require(dataSetLive(setId), "Data set not live");
        require(nPieces > 0, "Must add at least one piece");
        require(storageProvider[setId] == msg.sender, "Only the storage provider can add pieces");
        uint256 firstAdded = nextPieceId[setId];
        uint256[] memory pieceIds = new uint256[](pieceData.length);


        for (uint256 i = 0; i < nPieces; i++) {
            addOnePiece(setId, i, pieceData[i]);
            pieceIds[i] = firstAdded + i;
        }
        emit PiecesAdded(setId, pieceIds);

        address listenerAddr = dataSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).piecesAdded(setId, firstAdded, pieceData, extraData);
        }

        return firstAdded;
    }

    error IndexedError(uint256 idx, string msg);

    function addOnePiece(uint256 setId, uint256 callIdx, Cids.Cid calldata piece) internal returns (uint256) {
        (uint256 padding, uint8 height, ) = Cids.validateCommPv2(piece);
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
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        require(dataSetLive(setId), "Data set not live");
        require(storageProvider[setId] == msg.sender, "Only the storage provider can schedule removal of pieces");
        require(pieceIds.length + scheduledRemovals[setId].length <= MAX_ENQUEUED_REMOVALS, "Too many removals wait for next proving period to schedule");

        for (uint256 i = 0; i < pieceIds.length; i++){
            require(pieceIds[i] < nextPieceId[setId], "Can only schedule removal of existing pieces");
            scheduledRemovals[setId].push(pieceIds[i]);
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
        uint256 initialGas = gasleft();
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
                bool ok = MerkleVerify.verify(proofs[i].proof, pieceHash, proofs[i].leaf, challenges[i].offset, pieceHeight);
                require(ok, "proof did not verify");
            }
        }


        // Note: We don't want to include gas spent on the listener call in the fee calculation
        // to only account for proof verification fees and avoid gamability by getting the listener
        // to do extraneous work just to inflate the gas fee.
        //
        // (add 32 bytes to the `callDataSize` to also account for the `setId` calldata param)
        uint256 gasUsed = (initialGas - gasleft()) + ((calculateCallDataSize(proofs) + 32) * 1300);
        uint256 refund = calculateAndBurnProofFee(setId, gasUsed);

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
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Transfer failed.");
        }
    }

    function calculateProofFee(uint256 setId, uint256 estimatedGasFee) public returns (uint256) {
        uint256 rawSize = 32 * challengeRange[setId];
        (uint64 filUsdPrice, int32 filUsdPriceExpo) = getFILUSDPrice();

        return PDPFees.proofFeeWithGasFeeBound(
            estimatedGasFee,
            filUsdPrice,
            filUsdPriceExpo,
            rawSize,
            block.number - dataSetLastProvenEpoch[setId]
        );
    }

    function calculateAndBurnProofFee(uint256 setId, uint256 gasUsed) internal returns (uint256 refund) {
        uint256 estimatedGasFee = gasUsed * block.basefee;
        uint256 rawSize = 32 * challengeRange[setId];
        (uint64 filUsdPrice, int32 filUsdPriceExpo) = getFILUSDPrice();

        uint256 proofFee = PDPFees.proofFeeWithGasFeeBound(
            estimatedGasFee,
            filUsdPrice,
            filUsdPriceExpo,
            rawSize,
            block.number - dataSetLastProvenEpoch[setId]
        );
        burnFee(proofFee);
        emit ProofFeePaid(setId, proofFee, filUsdPrice, filUsdPriceExpo);

        return msg.value - proofFee; // burnFee asserts that proofFee <= msg.value;
    }

    function calculateCallDataSize(IPDPTypes.Proof[] calldata proofs) internal pure returns (uint256) {
        uint256 callDataSize = 0;
        for (uint256 i = 0; i < proofs.length; i++) {
            // 64 for the (leaf + abi encoding overhead ) + each element in the proof is 32 bytes
            callDataSize += 64 + (proofs[i].proof.length * 32);
        }
        return callDataSize;
    }

    function getRandomness(uint256 epoch) public view returns (uint256) {
        // Call the precompile
        (bool success, bytes memory result) = RANDOMNESS_PRECOMPILE.staticcall(abi.encodePacked(epoch));

        // Check if the call was successful
        require(success, "Randomness precompile call failed");

        // Decode and return the result
        return abi.decode(result, (uint256));
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
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
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

            for (uint256 i = 0; i < nRemovals; i++) {
                removalsToProcess[i] = removals[removals.length - 1];
                removals.pop();
            }

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
            PDPListener(listenerAddr).nextProvingPeriod(setId, nextChallengeEpoch[setId], dataSetLeafCount[setId], extraData);
        }
        emit NextProvingPeriod(setId, challengeEpoch, dataSetLeafCount[setId]);
    }

    // removes pieces from a data set's state.
    function removePieces(uint256 setId, uint256[] memory pieceIds) internal {
        require(dataSetLive(setId), "Data set not live");
        uint256 totalDelta = 0;
        for (uint256 i = 0; i < pieceIds.length; i++){
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
    function findOnePieceId(uint256 setId, uint256 leafIndex, uint256 top) internal view returns (IPDPTypes.PieceIdAndOffset memory) {
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
    function findPieceIds(uint256 setId, uint256[] calldata leafIndexs) public view returns (IPDPTypes.PieceIdAndOffset[] memory) {
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

    event PriceOracleFailure(bytes reason);

    // Add function to get FIL/USD price
    function getFILUSDPrice() public returns (uint64, int32) {
        // Get FIL/USD price no older than 1 day
        try PYTH.getPriceNoOlderThan(
            FIL_USD_PRICE_FEED_ID,
            SECONDS_IN_DAY
        ) returns (PythStructs.Price memory priceData) {
            require(priceData.price > 0, "failed to validate: price must be greater than 0");
            // Return the price and exponent representing USD per FIL
            return (uint64(priceData.price), priceData.expo);
        }   catch (bytes memory reason) {
            // Log issue and fallback on latest unsafe price data
            emit PriceOracleFailure(reason);
            PythStructs.Price memory priceData = PYTH.getPriceUnsafe(FIL_USD_PRICE_FEED_ID);
            require(priceData.price > 0, "failed to validate: price must be greater than 0");
            return (uint64(priceData.price), priceData.expo);
        }
    }
}
