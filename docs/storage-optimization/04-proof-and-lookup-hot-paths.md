# Step 4: Convert proof and Fenwick lookup hot paths

## Objective

Make challenge lookup and possession proof verification consume compact metadata directly, without reconstructing PieceCIDv2 in the proof path.

## Prerequisite

Step 3 appends complete `PieceV2` records and stores correct Fenwick partial sums in their metadata.

## Scope

Primary symbols in `src/PDPVerifier.sol`:

- `findOnePieceId`
- `findPieceIds`
- `provePossession`
- any internal compact-record accessor needed by these paths

CID-returning getters, pagination, CID search, removal, and cleanup remain for later steps.

## Required change

1. Replace every `sumTreeCounts[setId][index]` read in Fenwick lookup with one compact record load and `_pieceSum(metadata)`.
2. Replace `nextPieceId[setId]` in lookup bounds/top calculations with `compactPieces[setId].length`.
3. Preserve the existing Fenwick traversal, candidate comparison, leaf-index bounds, returned piece ID, and returned within-piece offset.
4. In `provePossession`, load the selected `PieceV2` record and use:
   - `piece.root` as the Merkle root;
   - packed height plus one as the verifier height.
5. Do not call `getPieceCid`, `CommPv2FromDigest`, `digestFromCid`, or `heightFromCid` from the proof loop.
6. Avoid loading the same compact metadata more than once for a single candidate decision. Cache values locally where Solidity would otherwise repeat an SLOAD.
7. Keep fee handling, challenge generation, listener callbacks, and event behavior unchanged.

## Invariants

- `findOnePieceId` may traverse removed nodes because their metadata retains updated Fenwick sums.
- A challenge selected from `challengeRange` must resolve to a live piece; this is maintained by the existing removal/sum-tree semantics.
- The root and height used by proofs come from the same canonical CID decoded during addition.

## Focused tests

Run/adapt the existing Fenwick and proof coverage for:

- a singleton piece;
- several differently sized pieces;
- leaf indices at piece boundaries;
- batched `findPieceIds` results;
- a valid proof against a compactly stored root;
- rejection of a proof built for a different root or height.

If removal-based lookup tests fail because removal is not yet migrated, record and defer only those cases to step 6.

## Acceptance

- Proof verification performs no CID reconstruction.
- Fenwick lookup reads no legacy sum mapping and uses compact array length.
- Non-removal lookup and proof tests pass.
- The repository builds without reintroducing legacy writes.

## Handoff

Record:

- compact accessor/load patterns used in the hot loop;
- tests passed and removal-dependent tests deferred;
- any observed repeated storage load that remains and why;
- confirmation that proof root and height no longer come from dynamic CID bytes.
