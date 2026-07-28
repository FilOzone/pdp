# Step 5: Convert getters, pagination, and CID search

## Objective

Move every remaining read-only piece path and scheduling liveness check to compact storage while preserving the public ABI and canonical CID output.

## Prerequisite

Steps 1–4 provide canonical decoding/reconstruction, compact records, compact addition, Fenwick lookup, and direct proof verification.

## Scope

Primary symbols in `src/PDPVerifier.sol`:

- `pieceLive`
- `pieceChallengable`
- `getNextPieceId`
- `getPieceCid`
- `getPieceLeafCount`
- `getActivePieceCount`
- `getActivePieces`
- `getActivePiecesByCursor`
- `findPieceIdsByCid`
- `schedulePieceDeletions`
- any shared compact read/reconstruction helper

Do not migrate ordinary removal or cleanup in this step.

## Required behavior

1. Treat `compactPieces[setId].length` as the exclusive upper bound and next ID.
2. Preserve mapping-like default behavior where public getters previously accepted an out-of-range ID:
   - leaf count returns zero;
   - CID returns an empty `Cids.Cid` unless existing tests/documented behavior establishes a revert.
   Do not allow an accidental Solidity array-bounds panic to redefine the API.
3. Determine liveness from a nonzero packed leaf count. A zero root is not a valid liveness sentinel.
4. Reconstruct canonical CIDs only at CID-returning boundaries using padding, height, and root.
5. Pagination must skip records with zero leaf count and retain existing offset/cursor/`hasMore` semantics.
6. `findPieceIdsByCid` must decode the target once, then compare root, padding, and height directly. Do not reconstruct/hash every stored CID.
7. Decide malformed search-query behavior explicitly and cover it with a test. Preferred prototype behavior is canonical validation and revert, matching the new rejection rule; do not leave accidental panic behavior.
8. Scheduling validates `pieceId < compact length` and nonzero packed leaf count.
9. Remove all read-only references to `pieceCids`, `pieceLeafCounts`, and `nextPieceId`.

## Tests

Cover:

- exact CID round trip for zero and multibyte padding;
- leaf-count getter and liveness for live, deleted/default, and out-of-range IDs;
- next ID before and after multiple append batches;
- offset and cursor pagination with holes;
- `hasMore` at page boundaries;
- duplicate CID matches;
- no match for a canonical different CID;
- explicit malformed CID-search behavior;
- scheduling rejects out-of-range, deleted, and duplicate IDs.

Removal-created holes may still depend on step 6. Tests can use the existing harness to construct equivalent compact metadata temporarily, but do not add production test hooks.

## Acceptance

- All listed paths use compact storage and compact length.
- Returned CIDs byte-equal canonical input CIDs.
- Search performs one query decode and field comparisons.
- Reader/pagination/search/scheduling tests pass except failures explicitly requiring migrated removal.
- No legacy read is added as fallback.

## Handoff

Record:

- out-of-range getter semantics retained;
- malformed CID-search semantics selected;
- reconstruction helper and call sites;
- targeted test results;
- remaining legacy mapping references, which should be mutation/cleanup or tests only.
