// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

// pdp-conform stateful suite for PDPVerifier.
//
// Every action is applied to two data sets with the same pieces: one in the v3.5 compact
// piece storage and one in the legacy mapping storage. After every action the invariants
// check both against an independent model (a plain array of leaf counts and a FIFO of
// scheduled removals) and against each other. Proofs are built from real SHA254 trees, so
// "an honest provider can always prove" and "a wrong leaf never verifies" are checked on
// the real verifier, not a mock.

import {Test} from "forge-std/Test.sol";
import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";
import {GET_BEACON_RANDOMNESS} from "fvm-solidity/FVMPrecompiles.sol";
import {FVMGetBeaconRandomness} from "fvm-solidity/mocks/FVMGetBeaconRandomness.sol";
import {Cids} from "../src/Cids.sol";
import {BitOps} from "../src/BitOps.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {PDPFees} from "../src/Fees.sol";
import {MerkleProve} from "../src/Proofs.sol";
import {IPDPTypes} from "../src/interfaces/IPDPTypes.sol";
import {
    LEGACY_PIECE_STORAGE_ID_LIMIT_SLOT,
    PIECE_CIDS_SLOT,
    PIECE_LEAF_COUNTS_SLOT,
    SUM_TREE_COUNTS_SLOT,
    COMPACT_PIECES_SLOT,
    SCHEDULED_REMOVALS_SLOT
} from "../src/PDPVerifierLayout.sol";

contract PDPModelHandler is Test {
    uint256 constant FINALITY = 2;
    uint256 constant MAX_LEAVES = 40;

    PDPVerifier public verifier;
    uint256 public compactSet;
    uint256 public legacySet;

    // ---- model ----
    uint256[] public leafCounts; // per piece id; 0 once removed
    uint256[] public salts; // tree content seed per piece id
    uint256[] public queue; // scheduled removals, in order
    mapping(uint256 => bool) public queued;
    uint256 public challengeRange;
    bool public challengeLive; // a challenge is scheduled and not invalidated

    // ---- stats ----
    uint256 public adds;
    uint256 public removals;
    uint256 public periods;
    uint256 public proofsOk;
    uint256 public forgedRejected;

    constructor(PDPVerifier v) {
        verifier = v;
    }

    function init() external {
        compactSet = verifier.createDataSet{value: PDPFees.cleanupDeposit()}(address(0), "");
        vm.store(address(verifier), LEGACY_PIECE_STORAGE_ID_LIMIT_SLOT, bytes32(0));
        legacySet = verifier.createDataSet{value: PDPFees.cleanupDeposit()}(address(0), "");
        vm.store(address(verifier), LEGACY_PIECE_STORAGE_ID_LIMIT_SLOT, bytes32(legacySet));
        require(verifier.legacyPieceStorageIdLimit() == legacySet, "boundary");
    }

    receive() external payable {}

    function pieceCount() external view returns (uint256) {
        return leafCounts.length;
    }

    function queueLength() external view returns (uint256) {
        return queue.length;
    }

    function totalLeaves() public view returns (uint256 t) {
        for (uint256 i = 0; i < leafCounts.length; i++) {
            t += leafCounts[i];
        }
    }

    // Model lookup: which piece holds data-set leaf `idx`, and at what offset.
    function modelFind(uint256 idx) public view returns (uint256 pieceId, uint256 offset) {
        uint256 acc;
        for (uint256 i = 0; i < leafCounts.length; i++) {
            if (idx < acc + leafCounts[i]) return (i, idx - acc);
            acc += leafCounts[i];
        }
        revert("model: index out of range");
    }

    // ---- trees ----
    function _leaves(uint256 salt, uint256 n) internal pure returns (bytes32[] memory l) {
        l = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            // fr32 leaves have the top two bits of the last byte clear
            l[i] = keccak256(abi.encode(salt, i)) & bytes32(uint256(type(uint256).max) >> 2);
        }
    }

    function _tree(uint256 pieceId) internal view returns (bytes32[][] memory) {
        return MerkleProve.buildTree(_leaves(salts[pieceId], leafCounts[pieceId]));
    }

    // Smallest tree holding `n` leaves; padding chosen so Cids.leafCount == n (same rule as the repo's tests).
    function _cid(bytes32 root, uint256 n, uint256 extraHeight) internal pure returns (Cids.Cid memory) {
        uint8 height = n == 1 ? 0 : uint8(256 - BitOps.clz(n - 1));
        height += uint8(extraHeight);
        uint256 paddingLeaves = (uint256(1) << height) - n;
        uint256 padding = (paddingLeaves * 32 * 127 + 127) / 128;
        return Cids.CommPv2FromDigest(padding, height, root);
    }

    // ---- actions ----
    function addPieces(uint256 seed, uint8 count) external {
        uint256 n = bound(count, 1, 4);
        Cids.Cid[] memory pieces = new Cids.Cid[](n);
        uint256 first = leafCounts.length;
        for (uint256 i = 0; i < n; i++) {
            uint256 lc = bound(uint256(keccak256(abi.encode(seed, i))), 1, MAX_LEAVES);
            uint256 salt = uint256(keccak256(abi.encode(seed, i, "salt")));
            leafCounts.push(lc);
            salts.push(salt);
            bytes32 root = MerkleProve.buildTree(_leaves(salt, lc))[0][0];
            // Pieces are only provable on the tree the CID names, so keep the minimal height.
            pieces[i] = _cid(root, lc, 0);
        }
        assertEq(verifier.addPieces(compactSet, address(0), pieces, ""), first, "compact first id");
        assertEq(verifier.addPieces(legacySet, address(0), pieces, ""), first, "legacy first id");
        adds += n;
    }

    function scheduleRemovals(uint256 seed, uint8 count) external {
        uint256 live;
        for (uint256 i = 0; i < leafCounts.length; i++) {
            if (leafCounts[i] > 0 && !queued[i]) live++;
        }
        if (live == 0) return;
        uint256 k = bound(count, 1, live < 3 ? live : 3);
        uint256[] memory ids = new uint256[](k);
        uint256 picked;
        uint256 start = seed % leafCounts.length;
        for (uint256 j = 0; j < leafCounts.length && picked < k; j++) {
            uint256 i = (start + j * 7 + 1) % leafCounts.length; // 7 is coprime with nothing special; dedupe below
            if (leafCounts[i] > 0 && !queued[i]) {
                queued[i] = true;
                ids[picked++] = i;
            }
        }
        assembly {
            mstore(ids, picked)
        }
        if (picked == 0) return;
        for (uint256 j = 0; j < picked; j++) {
            queue.push(ids[j]);
        }
        verifier.schedulePieceDeletions(compactSet, ids, "");
        verifier.schedulePieceDeletions(legacySet, ids, "");
    }

    function processDeletions(uint8 count) external {
        if (queue.length == 0) return;
        uint256 k = bound(count, 1, queue.length);
        // Contract pops from the end of the queue.
        for (uint256 j = 0; j < k; j++) {
            uint256 id = queue[queue.length - 1];
            queue.pop();
            queued[id] = false;
            leafCounts[id] = 0;
            removals++;
        }
        bool hadChallenge = challengeLive;
        verifier.processPieceDeletions(compactSet, k);
        verifier.processPieceDeletions(legacySet, k);
        challengeLive = false;
        assertEq(verifier.getNextChallengeEpoch(compactSet), 0, "compact: deletion left challenge scheduled");
        assertEq(verifier.getNextChallengeEpoch(legacySet), 0, "legacy: deletion left challenge scheduled");
        // Adversarial: a deletion invalidates the pending challenge, so a proof must not be accepted
        // until the next proving period, even one that would otherwise verify.
        if (hadChallenge) {
            IPDPTypes.Proof[] memory none = new IPDPTypes.Proof[](1);
            vm.expectRevert();
            verifier.provePossession{value: 1 ether}(compactSet, none);
            vm.expectRevert();
            verifier.provePossession{value: 1 ether}(legacySet, none);
        }
    }

    function nextProvingPeriod(uint256 rnd, uint8 delay) public {
        if (queue.length != 0) {
            // Adversarial: a new period must not start while removals are pending.
            uint256 e = block.number + FINALITY;
            vm.expectRevert();
            verifier.nextProvingPeriod(compactSet, e, "");
            vm.expectRevert();
            verifier.nextProvingPeriod(legacySet, e, "");
            return;
        }
        uint256 total = totalLeaves();
        if (total == 0 && challengeRange == 0) return;
        uint256 d = bound(delay, FINALITY, FINALITY + 20);
        uint256 epoch = block.number + d;
        FVMGetBeaconRandomness(GET_BEACON_RANDOMNESS)
            .mockBeaconRandomness(epoch, uint256(keccak256(abi.encode(rnd))) | 1);
        verifier.nextProvingPeriod(compactSet, epoch, "");
        verifier.nextProvingPeriod(legacySet, epoch, "");
        challengeRange = total;
        challengeLive = total > 0;
        periods++;
    }

    // Adversarial: re-scheduling a queued piece, or scheduling a removed / unknown piece, must revert.
    function scheduleInvalid(uint256 seed) external {
        uint256[] memory ids = new uint256[](1);
        uint256 n = leafCounts.length;
        if (queue.length > 0 && seed % 3 == 0) {
            ids[0] = queue[seed % queue.length];
        } else if (n > 0 && seed % 3 == 1) {
            uint256 i = seed % n;
            if (leafCounts[i] != 0) return;
            ids[0] = i;
        } else {
            ids[0] = n + (seed % 5);
        }
        vm.expectRevert();
        verifier.schedulePieceDeletions(compactSet, ids, "");
        vm.expectRevert();
        verifier.schedulePieceDeletions(legacySet, ids, "");
    }

    uint256 public cleanups;

    // Lifecycle: delete both data sets, drain them with cleanupPieces in random batch sizes,
    // check termination, state teardown and a single deposit refund, then start fresh sets.
    function deleteAndCleanup(uint8 batch) external {
        if (leafCounts.length == 0) return;
        uint256 maxPieces = bound(batch, 1, 7);
        uint256[2] memory sets = [compactSet, legacySet];
        for (uint256 k = 0; k < 2; k++) {
            uint256 id = sets[k];
            uint256 n = leafCounts.length;
            // Adversarial: inside the activity window only the provider may delete or clean up.
            vm.prank(address(0xBAD));
            vm.expectRevert();
            verifier.deleteDataSet(id, "");
            verifier.deleteDataSet(id, "");
            vm.prank(address(0xBAD));
            vm.expectRevert();
            verifier.cleanupPieces(id, maxPieces);
            assertFalse(verifier.dataSetLive(id), "live after delete");
            uint256 before = address(this).balance;
            uint256 calls;
            bool done;
            while (!done) {
                done = verifier.cleanupPieces(id, maxPieces);
                calls++;
                require(calls <= leafCounts.length / maxPieces + 1, "cleanup did not terminate in ceil(n/max) calls");
            }
            assertEq(address(this).balance - before, PDPFees.cleanupDeposit(), "deposit refund");
            _assertStorageReleased(id, n);
            vm.expectRevert();
            verifier.getNextPieceId(id);
            vm.expectRevert();
            verifier.cleanupPieces(id, 1);
        }
        cleanups++;
        delete leafCounts;
        delete salts;
        for (uint256 i = 0; i < queue.length; i++) {
            queued[queue[i]] = false;
        }
        delete queue;
        challengeRange = 0;
        challengeLive = false;
        this.init();
    }

    function _slot2(bytes32 base, uint256 a, uint256 b) internal pure returns (bytes32) {
        return keccak256(abi.encode(b, keccak256(abi.encode(a, base))));
    }

    // Cleanup exists to release storage. Read the raw slots to check nothing is left behind.
    function _assertStorageReleased(uint256 id, uint256 n) internal view {
        address v = address(verifier);
        for (uint256 i = 0; i < n; i++) {
            assertEq(vm.load(v, _slot2(PIECE_LEAF_COUNTS_SLOT, id, i)), bytes32(0), "legacy leaf count left in storage");
            assertEq(vm.load(v, _slot2(SUM_TREE_COUNTS_SLOT, id, i)), bytes32(0), "legacy sum tree left in storage");
            assertEq(vm.load(v, _slot2(PIECE_CIDS_SLOT, id, i)), bytes32(0), "legacy CID left in storage");
        }
        bytes32 arr = keccak256(abi.encode(id, COMPACT_PIECES_SLOT));
        assertEq(vm.load(v, arr), bytes32(0), "compact piece array length left");
        bytes32 first = keccak256(abi.encode(arr));
        for (uint256 i = 0; i < 2 * n; i++) {
            assertEq(vm.load(v, bytes32(uint256(first) + i)), bytes32(0), "compact piece slot left");
        }
        assertEq(vm.load(v, keccak256(abi.encode(id, SCHEDULED_REMOVALS_SLOT))), bytes32(0), "removal queue left");
    }

    function roll(uint8 blocks) external {
        vm.roll(block.number + bound(blocks, 1, 30));
    }

    function prove(uint8 nChallenges, uint256 forgeSeed) external {
        if (!challengeLive) nextProvingPeriod(forgeSeed, uint8(forgeSeed >> 200));
        if (!challengeLive) return;
        uint256 epoch = verifier.getNextChallengeEpoch(compactSet);
        if (block.number < epoch) vm.roll(epoch);
        uint256 n = bound(nChallenges, 1, 5);
        _prove(compactSet, n, forgeSeed);
        _prove(legacySet, n, forgeSeed);
        challengeLive = false; // a period is proven once; FWSS-style flow moves on
    }

    function _prove(uint256 setId, uint256 n, uint256 forgeSeed) internal {
        uint256 seed = verifier.getRandomness(verifier.getNextChallengeEpoch(setId));
        IPDPTypes.Proof[] memory proofs = new IPDPTypes.Proof[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 idx = uint256(keccak256(abi.encodePacked(seed, setId, uint64(i)))) % challengeRange;
            (uint256 pid, uint256 off) = modelFind(idx);
            bytes32[][] memory tree = _tree(pid);
            proofs[i] = IPDPTypes.Proof(tree[tree.length - 1][off], MerkleProve.buildProof(tree, off));
        }
        uint256 fee = verifier.calculateProofFee(setId);

        // Soundness: corrupt one leaf or one sibling; the verifier must reject.
        uint256 which = forgeSeed % n;
        bytes32 saved = proofs[which].leaf;
        if (proofs[which].proof.length > 0 && (forgeSeed >> 8) % 2 == 1) {
            uint256 lvl = (forgeSeed >> 16) % proofs[which].proof.length;
            bytes32 s = proofs[which].proof[lvl];
            proofs[which].proof[lvl] = s ^ bytes32(uint256(1));
            vm.expectRevert();
            verifier.provePossession{value: fee}(setId, proofs);
            proofs[which].proof[lvl] = s;
        } else {
            proofs[which].leaf = saved ^ bytes32(uint256(1) << 8);
            vm.expectRevert();
            verifier.provePossession{value: fee}(setId, proofs);
            proofs[which].leaf = saved;
        }
        forgedRejected++;

        // Liveness: the honest proof, built from the model's challenge -> piece mapping, verifies.
        verifier.provePossession{value: fee}(setId, proofs);
        proofsOk++;
    }
}

// Handler assertions revert, so fail-on-revert makes them count as invariant failures.
/// forge-config: default.invariant.runs = 64
/// forge-config: default.invariant.depth = 100
/// forge-config: default.invariant.fail-on-revert = true
/// forge-config: fast.invariant.runs = 64
/// forge-config: fast.invariant.depth = 100
/// forge-config: fast.invariant.fail-on-revert = true
contract PDPInvariantsTest is MockFVMTest {
    PDPVerifier verifier;
    PDPModelHandler handler;

    function setUp() public override {
        super.setUp();
        PDPVerifier impl = new PDPVerifier(1, 2);
        verifier = PDPVerifier(
            address(new MyERC1967Proxy(address(impl), abi.encodeWithSelector(PDPVerifier.initialize.selector)))
        );
        handler = new PDPModelHandler(verifier);
        vm.deal(address(handler), 1_000_000 ether);
        handler.init();
        targetContract(address(handler));
        bytes4[] memory sel = new bytes4[](8);
        sel[6] = PDPModelHandler.scheduleInvalid.selector;
        sel[7] = PDPModelHandler.deleteAndCleanup.selector;
        sel[0] = PDPModelHandler.addPieces.selector;
        sel[1] = PDPModelHandler.scheduleRemovals.selector;
        sel[2] = PDPModelHandler.processDeletions.selector;
        sel[3] = PDPModelHandler.nextProvingPeriod.selector;
        sel[4] = PDPModelHandler.roll.selector;
        sel[5] = PDPModelHandler.prove.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sel}));
    }

    function _sets() internal view returns (uint256 c, uint256 l) {
        return (handler.compactSet(), handler.legacySet());
    }

    /// Data-set leaf count equals the model's sum of live leaf counts, in both storage layouts.
    function invariant_leafCountMatchesModel() public view {
        (uint256 c, uint256 l) = _sets();
        uint256 t = handler.totalLeaves();
        assertEq(verifier.getDataSetLeafCount(c), t, "compact leaf count");
        assertEq(verifier.getDataSetLeafCount(l), t, "legacy leaf count");
    }

    /// Per-piece state agrees with the model and across layouts (leaf count, liveness, CID bytes).
    function invariant_piecesMatchModel() public view {
        (uint256 c, uint256 l) = _sets();
        uint256 n = handler.pieceCount();
        assertEq(verifier.getNextPieceId(c), n, "compact next id");
        assertEq(verifier.getNextPieceId(l), n, "legacy next id");
        uint256 live;
        for (uint256 i = 0; i < n; i++) {
            uint256 lc = handler.leafCounts(i);
            assertEq(verifier.getPieceLeafCount(c, i), lc, "compact piece leaf count");
            assertEq(verifier.getPieceLeafCount(l, i), lc, "legacy piece leaf count");
            assertEq(verifier.pieceLive(c, i), lc > 0, "compact pieceLive");
            assertEq(verifier.pieceLive(l, i), lc > 0, "legacy pieceLive");
            assertEq(verifier.getPieceCid(c, i).data, verifier.getPieceCid(l, i).data, "CID differs across layouts");
            if (lc > 0) live++;
        }
        assertEq(verifier.getActivePieceCount(c), live, "compact active count");
        assertEq(verifier.getActivePieceCount(l), live, "legacy active count");
    }

    /// Every leaf index maps to the same (piece, offset) as a linear scan of the model.
    /// This is the challenge -> piece mapping the provider's proof depends on.
    function invariant_sumTreeLookupMatchesModel() public view {
        (uint256 c, uint256 l) = _sets();
        uint256 t = handler.totalLeaves();
        if (t == 0) return;
        uint256 step = t / 97 + 1;
        uint256 m = (t + step - 1) / step;
        uint256[] memory idx = new uint256[](m + 1);
        for (uint256 j = 0; j < m; j++) {
            idx[j] = j * step;
        }
        idx[m] = t - 1;
        IPDPTypes.PieceIdAndOffset[] memory rc = verifier.findPieceIds(c, idx);
        IPDPTypes.PieceIdAndOffset[] memory rl = verifier.findPieceIds(l, idx);
        for (uint256 j = 0; j <= m; j++) {
            (uint256 pid, uint256 off) = handler.modelFind(idx[j]);
            assertEq(rc[j].pieceId, pid, "compact pieceId");
            assertEq(rc[j].offset, off, "compact offset");
            assertEq(rl[j].pieceId, pid, "legacy pieceId");
            assertEq(rl[j].offset, off, "legacy offset");
        }
    }

    /// The scheduled-removal queue matches the model in order.
    function invariant_removalQueueMatchesModel() public view {
        (uint256 c, uint256 l) = _sets();
        uint256[] memory qc = verifier.getScheduledRemovals(c);
        uint256[] memory ql = verifier.getScheduledRemovals(l);
        assertEq(qc.length, handler.queueLength(), "compact queue length");
        assertEq(ql.length, handler.queueLength(), "legacy queue length");
        for (uint256 i = 0; i < qc.length; i++) {
            assertEq(qc[i], handler.queue(i), "compact queue entry");
            assertEq(ql[i], handler.queue(i), "legacy queue entry");
        }
    }

    /// Challenge range never exceeds the live leaf count while a challenge is scheduled.
    function invariant_challengeRangeSound() public view {
        (uint256 c, uint256 l) = _sets();
        assertEq(verifier.getChallengeRange(c), verifier.getChallengeRange(l), "challenge range differs");
        if (handler.challengeLive()) {
            assertEq(verifier.getChallengeRange(c), handler.challengeRange(), "challenge range vs model");
            assertLe(verifier.getChallengeRange(c), verifier.getDataSetLeafCount(c), "range > leaves");
            assertGt(verifier.getNextChallengeEpoch(c), 0, "live challenge but epoch 0");
        }
    }

    function afterInvariant() public view {
        // Printed in the CI log so a run shows it exercised proofs, not just adds.
        console_log();
    }

    function console_log() internal view {
        // forge-std console without importing it into every contract
        (bool ok,) = address(0x000000000000000000636F6e736F6c652e6c6f67)
            .staticcall(
                abi.encodeWithSignature(
                    "log(string,uint256,uint256,uint256)",
                    "adds/removals/proofs:",
                    handler.adds(),
                    handler.removals(),
                    handler.proofsOk()
                )
            );
        ok;
    }
}
