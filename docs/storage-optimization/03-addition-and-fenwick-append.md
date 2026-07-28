# Step 3: Convert addition and Fenwick append

## Objective

Make every newly added piece use one root slot and one initial metadata write, with the Fenwick partial sum included in that metadata.

## Prerequisites

- Step 1 provides canonical `(padding, height, root)` decoding.
- Step 2 provides `PieceV2`, `compactPieces`, masks, packing helpers, and generated layout artifacts.

## Scope

Primary symbols in `src/PDPVerifier.sol`:

- `_addPiecesToDataSet`
- `addOnePiece`
- `sumTreeAdd`
- addition-specific internal helpers

Do not migrate proofs, getters, ordinary removal, or cleanup in this step.

## Required behavior

1. `firstAdded` is the compact array length before appending.
2. For each calldata CID:
   - validate/decode it once;
   - enforce padding and `MAX_PIECE_SIZE_LOG2` rules;
   - calculate leaf count;
   - enforce the 51-bit leaf field;
   - compute the Fenwick partial sum from prior compact metadata;
   - enforce the 144-bit sum limit;
   - append `PieceV2(root, packedMetadata)`.
3. Refactor `sumTreeAdd` into a read-only calculation. It must return the new node sum and must not perform a separate storage write.
4. Accumulate added leaf count in memory and update `dataSetLeafCount[setId]` once per batch.
5. Reject a batch that would make the dataset total exceed the 144-bit maximum before any packed truncation is possible. Transaction rollback remains the atomicity guarantee.
6. Keep piece IDs, `PiecesAdded`, listener callback arguments, and return values unchanged.
7. Use ordinary compiler-managed array `push()` in this prototype. Do not add assembly to resize the array once.
8. Stop writing all four legacy piece variables in the addition path, including `nextPieceId`.

## Fenwick invariant

For appended piece ID `j`, metadata stores the sum of the range selected by `ctz(j + 1)`, exactly matching the old `sumTreeCounts[setId][j]` definition. Prior nodes are read through the compact sum accessor.

## Intermediate-state warning

After this step, full behavioral tests that still read legacy mappings are expected to fail. The contract must compile and focused addition/packing checks must prove compact writes are correct. Do not restore legacy writes as a temporary bridge; steps 4–6 migrate consumers.

## Focused tests

Add or adapt a harness test to verify, without public legacy getters:

- first batch begins at ID 0;
- a later batch begins at the prior compact array length;
- array length increments monotonically;
- roots and decoded fields match input CIDs;
- Fenwick node sums for a known leaf-count sequence match expected partial sums;
- `dataSetLeafCount` increases by the batch total;
- an invalid item reverts the entire batch;
- the 144-bit total guard rejects overflow.

## Acceptance

- Addition no longer writes `pieceCids`, `pieceLeafCounts`, `sumTreeCounts`, or `nextPieceId`.
- Each piece receives exactly one initial metadata value containing its final append sum.
- Focused addition tests pass and the repository builds.
- No assembly array-length optimization is introduced.

## Handoff

Record:

- the new append helper signatures;
- how the dataset total and sum overflow are checked;
- focused test results;
- known full-suite failures attributable only to unmigrated readers/removers.
