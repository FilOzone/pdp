# Piece storage backwards-compatibility strategy

## Status and scope

The compact piece representation introduced on the current branch cannot replace the legacy representation for existing datasets: migrating all existing piece and Fenwick-tree state would be prohibitively expensive. The verifier will therefore support both representations indefinitely and select one representation for the lifetime of each dataset.

This document records the intended design, the workflows that require format-aware handling, and the tests required before the change is complete.

CID compatibility is intentionally parked. We will validate the CIDs currently stored on-chain and assume invalid CIDs have not been admitted. This work therefore does not preserve acceptance of non-canonical CID encodings or introduce a second CID decoder. CID handling should be revisited only if validation of existing state disproves that assumption.

## Goals

- Preserve all existing datasets without migrating their piece or Fenwick-tree state.
- Keep appending to an existing dataset in the representation chosen when that dataset was created.
- Store every newly created post-cutover dataset in `compactPieces`.
- Preserve the public behavior of dataset queries, proving, removal, deletion, cleanup, events, and listener callbacks.
- Keep format selection deterministic, permanent, and independent of whether either representation happens to be empty.
- Keep the compact addition path's storage savings.
- Remain below the EVM runtime bytecode limit. At the time this document was written, `PDPVerifier` compiled via IR to 21,335 bytes, leaving 3,241 bytes of runtime headroom.

## Non-goals

- Migrating legacy pieces into `compactPieces`.
- Mixing legacy and compact pieces inside one dataset.
- Detecting the representation by inspecting `compactPieces.length`, `nextPieceId`, or other dataset contents. Empty and deleted datasets make content-based detection ambiguous.
- Changing dataset IDs or reusing deleted dataset IDs.
- Preserving acceptance of malformed or non-canonical CIDs. This is parked pending validation of existing on-chain CIDs.
- Reworking authorization, fees, challenge generation, listener behavior, or public pagination semantics.

## Cutover marker

Append this state field after the existing compact piece mapping:

```solidity
uint64 public legacyPieceStorageIdLimit;
```

Its semantics are an exclusive upper bound:

```text
legacyPieceStorageIdLimit == 0
    The cutover has not been initialized. Conservatively use legacy storage.

setId < legacyPieceStorageIdLimit
    Use pieceCids, pieceLeafCounts, sumTreeCounts, and nextPieceId.

setId >= legacyPieceStorageIdLimit
    Use compactPieces.
```

The corresponding predicate should express the legacy case because zero has a safe meaning:

```solidity
function _usesLegacyPieceStorage(uint256 setId) internal view returns (bool) {
    uint64 limit = legacyPieceStorageIdLimit;
    return limit == 0 || setId < limit;
}
```

The marker must be the only representation decision. No workflow may infer the representation from current storage contents.

### Fresh deployment

`initialize` sets both counters explicitly:

```solidity
nextDataSetId = 1;
legacyPieceStorageIdLimit = 1;
```

Dataset ID zero remains the new-dataset sentinel. Every real dataset created by a fresh deployment is therefore compact.

### Upgrade from the legacy representation

`migrate` records the next unissued dataset ID:

```solidity
if (legacyPieceStorageIdLimit == 0) {
    legacyPieceStorageIdLimit = nextDataSetId;
}
```

At that point every issued dataset ID is below the limit. The limit itself names a dataset that does not yet exist and will become the first compact dataset if another dataset is created.

The zero check is mandatory. Future implementations will run newer reinitializers and must not move the boundary forward, because doing so would reinterpret already-compact datasets as legacy.

The intended operational path remains an atomic `upgradeToAndCall(newImplementation, migrateData)`. However, zero deliberately falls back to legacy storage so an upgrade that omits or delays `migrate` remains correct: datasets created before the eventual migration also use legacy storage, and the later migration puts the boundary after them.

### Why not initialize the marker on first dataset creation

Writing the limit during migration is preferable because:

- the cutover is fixed and observable in the upgrade transaction;
- no user transaction decides when the new format starts;
- delayed migration has a safe legacy fallback;
- dataset creation has no additional first-call state transition; and
- the monotonic `nextDataSetId` already provides the exact exclusive boundary.

## Implementation structure

Authorization, fees, event emission, listener calls, and proving-period transitions should remain single shared workflows. Only storage primitives should branch. Duplicating complete public workflows would encourage semantic drift and is risky given the current bytecode headroom.

Compute the format once near each workflow boundary and pass a `bool legacy` into internal helpers. This avoids repeatedly loading the marker inside scans and Fenwick traversals.

### Read adapters

The common read vocabulary should cover:

```solidity
function _pieceCount(uint256 setId, bool legacy) internal view returns (uint256);
function _pieceLeafCount(uint256 setId, uint256 pieceId, bool legacy) internal view returns (uint256);
function _pieceCidAt(uint256 setId, uint256 pieceId, bool legacy)
    internal
    view
    returns (Cids.Cid memory);
function _sumTreeValue(uint256 setId, uint256 pieceId, bool legacy)
    internal
    view
    returns (uint256);
```

Required behavior:

- Legacy count is `nextPieceId[setId]`; compact count is `compactPieces[setId].length`.
- Liveness is determined by a nonzero leaf count, never by a root.
- CID and leaf-count getters preserve the existing mapping-like empty/zero result for an out-of-range piece ID. Compact array access must check bounds before indexing.
- A compact CID is reconstructed only at CID-returning boundaries. The proof path reads compact root and height directly.

Small representation-specific helpers may be preferable where a unified return value would force unnecessary memory allocation. In particular, compact proof verification must not construct a CID merely to recover its root and height.

### Mutation adapters

The mutation vocabulary should include representation-aware addition, removal, sum updates, and cleanup:

```solidity
function _addOnePiece(..., bool legacy) internal returns (uint256 leafCount);
function _removeOnePiece(..., bool legacy) internal returns (uint256 leafCount);
function _updateSumTreeValue(..., bool legacy, bool clearPiece) internal;
function _cleanupPieceStorage(..., bool legacy) internal returns (bool done);
```

The public or batch-level workflow remains responsible for common validation, aggregate leaf-count updates, events, and listener callbacks.

### Fenwick algorithms

Prefer one Fenwick append, subtraction, and lookup algorithm using `_pieceCount` and `_sumTreeValue`. Representation-specific writes are unavoidable:

- Legacy sums live in `sumTreeCounts`.
- Compact sums live inside packed metadata.
- Legacy ordinary removal deletes the CID and leaf count while retaining the updated sum mapping.
- Compact ordinary removal clears the root and all non-sum metadata while retaining the updated sum in the removed node.

Only duplicate a Fenwick algorithm if measurements show that the shared adapter design is unacceptable and the resulting runtime bytecode still fits.

## Workflow inventory

Every direct reference to `compactPieces`, `pieceCids`, `pieceLeafCounts`, `sumTreeCounts`, or `nextPieceId` must fall into one of the following reviewed locations.

### Piece state and basic getters

Affected functions:

- `pieceLive`
- `pieceChallengable`
- `getNextPieceId`
- `getPieceCid`
- `getPieceLeafCount`

These should use the format predicate and read adapters. `pieceChallengable` must use the selected representation for the piece count, Fenwick lookup, and final piece leaf count.

### Active-piece scans and CID search

Affected functions:

- `getActivePieceCount`
- `getActivePieces`
- `getActivePiecesByCursor`
- `findPieceIdsByCid`

Keep one implementation of the pagination and `hasMore` rules. The loop obtains count, liveness, and returned CIDs through format-aware helpers.

For CID search:

- the legacy path compares the requested CID to the exact stored CID bytes;
- the compact path validates the query once and compares root, padding, and height;
- CID compatibility beyond currently valid stored CIDs remains parked.

### Addition

Affected functions:

- `_addPiecesToDataSet`
- `addOnePiece`, or its replacement
- `sumTreeAdd`

`firstAdded` comes from the selected representation's piece count. An old dataset continues writing all new pieces to the legacy mappings after upgrade. A compact dataset writes only `compactPieces`.

Compact metadata packing and total-sum overflow limits apply only where required by the compact representation. They must not accidentally reject an otherwise valid legacy dataset solely because its existing aggregate state cannot fit compact metadata.

Events and `piecesAdded` listener callbacks remain outside the representation branch.

### Scheduling and ordinary removal

Affected functions:

- `schedulePieceDeletions`
- `removePieces`
- `removeOnePiece`, or its replacement
- `sumTreeRemove`

Scheduling checks the selected representation's bounds and leaf-count liveness. Removal preserves stable piece IDs and does not shrink either representation during normal operation.

Legacy removal:

1. Read the delta from `pieceLeafCounts`.
2. Subtract it from the relevant `sumTreeCounts` nodes.
3. Delete the piece CID and leaf count.
4. Retain the adjusted sum-tree entries.

Compact removal:

1. Read the delta from packed metadata.
2. Subtract it from the relevant embedded sums.
3. Clear the removed root.
4. Clear the removed node's padding, height, and leaf count while retaining its adjusted sum.
5. Preserve other nodes' piece metadata while updating only their sums.

### Fenwick lookup and proofs

Affected functions:

- `findOnePieceId`
- `findPieceIds`
- `provePossession`

Fenwick lookup uses the selected piece count and sum source throughout one traversal.

Proof verification shares challenge generation, fees, proof iteration, listener notification, and events. Only retrieval of proof metadata differs:

- Legacy: obtain root and height from the stored CID.
- Compact: obtain root and height directly from `PieceV2`.

No compact proof should reconstruct a CID.

### Dataset deletion and incremental cleanup

Affected functions:

- `deleteDataSet`
- `cleanupPieces`
- `_finalizeCleanup`

`deleteDataSet` uses the selected piece count to distinguish an empty dataset from one that must enter cleanup mode.

Cleanup dispatches once by representation:

- Legacy cleanup deletes `pieceCids`, `pieceLeafCounts`, and `sumTreeCounts` from the end and decrements `nextPieceId`.
- Compact cleanup clears and pops `PieceV2` records from the end, reducing the array length.
- `_finalizeCleanup` remains shared and runs only after the selected representation's piece count reaches zero.

The historical pre-cleanup-mode case must be retained only for legacy storage:

```text
uses legacy storage
and storageProvider == address(0)
and nextPieceId > 0
```

Such datasets were deleted by an older implementation and their remaining piece mappings are permissionlessly cleanable. A compact dataset with a cleared provider must not activate this path.

## Testing strategy

### Upgrade fixture

Add a dedicated compatibility test contract using `MyERC1967Proxy`.

A test-only implementation or harness should populate the legacy mappings through the retained legacy path, with the marker forced to zero to represent pre-cutover state. Then:

1. Create multiple legacy datasets and add pieces.
2. Record the pre-upgrade `nextDataSetId`.
3. Upgrade with `upgradeToAndCall` and invoke `migrate`.
4. Assert `legacyPieceStorageIdLimit == preUpgradeNextDataSetId`.
5. Assert all existing dataset IDs route to legacy storage.
6. Create another dataset and assert its ID equals the limit and it routes to compact storage.
7. Upgrade once more with a higher reinitializer version and assert the nonzero limit is unchanged.

Also test an upgrade without `migrate`: existing operations and newly created datasets must remain legacy until migration is eventually called.

### Differential workflow fixture

Keep one legacy and one compact dataset in the same proxy. Populate them with equivalent valid CIDs and exercise the same public behavior:

- append one and multiple batches;
- read next piece ID, CID, leaf count, and liveness;
- enumerate active pieces with offset and cursor pagination;
- search duplicate and absent CIDs;
- query leaf-to-piece mappings at every piece boundary;
- schedule and apply removals through `nextProvingPeriod`;
- append after removal and verify IDs are not reused;
- submit a real valid possession proof;
- delete and clean incrementally; and
- compare events and listener callback arguments.

The expected storage representation differs, but observable behavior should match for valid CIDs.

### Boundary and lifecycle cases

Cover:

- fresh deployment initializes the limit to `1`;
- migration with no existing datasets sets the limit to `1`;
- the dataset immediately below the limit is legacy;
- the dataset at the limit is compact;
- an empty legacy dataset and an empty compact dataset;
- out-of-range piece getters;
- removed Fenwick nodes that retain nonzero partial sums;
- a legacy dataset appended after migration remains entirely legacy;
- a legacy dataset deleted before cleanup mode was introduced remains cleanable;
- a compact dataset with `storageProvider == 0` does not use the historical cleanup path; and
- a future migration does not move the limit.

The existing `testLegacyDeletedDataSetCleanupRequiresCleanupMode` currently creates a compact dataset and asserts that the removed legacy-mapping path is unavailable. Preserve that assertion as a compact-format test, rename it accordingly, and add a genuinely legacy fixture for the historical cleanup behavior.

### Storage isolation

Use the generated layout constants and `vm.load` to prove:

- legacy additions and removals do not touch the compact array header;
- compact additions do not change legacy `nextPieceId`;
- compact additions do not populate legacy CID, leaf-count, or sum mappings;
- partial cleanup decreases only the selected representation's count; and
- final cleanup clears every slot belonging to the selected representation.

The existing compact storage metric remains an acceptance criterion: four compact pieces occupy eight new piece slots and do not create legacy piece entries.

### Verification commands

During implementation, run focused tests first, then the complete gates:

```bash
forge test --via-ir --match-path test/PDPVerifierUpgradeCompatibility.t.sol -vv
forge test --via-ir --match-path test/PDPVerifierProofTest.t.sol -vv
forge test --via-ir --match-path test/CleanupPieces.t.sol -vv
forge build --sizes --via-ir
make check-layout
forge test --via-ir -vv
```

The runtime size measurement is a required acceptance gate, not informational output.

## Implementation sequence

1. Append `legacyPieceStorageIdLimit`, regenerate layout artifacts, and implement initialization/migration semantics.
2. Add the format predicate and representation-aware read adapters.
3. Route basic getters, scans, pagination, and CID search through the adapters.
4. Route addition and Fenwick append while retaining compact storage metrics.
5. Route scheduling, ordinary removal, and Fenwick subtraction.
6. Route Fenwick lookup and possession proofs.
7. Route dataset deletion and both incremental cleanup representations.
8. Add the proxy upgrade fixture and differential tests.
9. Run storage-layout, runtime-size, focused behavior, and full-suite verification.

Each step must leave no content-based format detection or unreviewed direct piece-storage access behind.

## Completion criteria

The compatibility work is complete only when:

- the migration records one immutable exclusive legacy-ID limit;
- fresh deployments use compact storage from dataset ID `1`;
- old datasets remain fully operable and continue using legacy storage;
- new datasets use compact storage exclusively;
- all query, add, remove, prove, delete, and cleanup workflows route by the limit;
- historical deleted legacy datasets remain cleanable;
- events and listener callbacks are representation-independent;
- compact storage metrics remain intact;
- storage layout validation passes;
- runtime bytecode remains deployable; and
- focused compatibility tests and the full suite pass.
