# Step 6: Convert ordinary removal and dataset cleanup

## Objective

Complete the compact storage cutover by migrating Fenwick subtraction, piece deletion, dataset deletion checks, and incremental cleanup.

## Prerequisite

Steps 3–5 make compact storage authoritative for addition, proof lookup, getters, pagination, search, and scheduling.

## Scope

Primary symbols in `src/PDPVerifier.sol`:

- `deleteDataSet`
- `cleanupPieces`
- `_finalizeCleanup` where cursor state is relevant
- `removePieces`
- `removeOnePiece`
- `sumTreeRemove`
- all remaining production references to legacy piece mappings and `nextPieceId`

## Ordinary removal contract

For each scheduled live piece:

1. Load its packed leaf count as `delta`.
2. Walk the same Fenwick node/ancestor sequence as the current implementation using compact array length as the top bound.
3. At each node, subtract `delta` from the packed 144-bit sum with checked arithmetic.
4. At the removed node itself, write metadata containing only the updated sum; padding, height, and leaf count become zero.
5. At ancestor nodes, preserve their padding, height, and leaf count while replacing only the sum.
6. Delete the removed piece root.
7. Do not shrink the array. IDs remain stable and are never reused.
8. Subtract the accumulated delta from `dataSetLeafCount` once per removal batch, as today.

A removed Fenwick node can retain a nonzero sum for earlier pieces in its covered range. Deleting the entire metadata word during ordinary removal is incorrect.

## Cleanup contract

1. Use compact array length for zero-piece detection and cleanup progress.
2. Process entries from the end, preserving current `maxPieces`, permission, cleanup-mode, deposit, and completion semantics.
3. Clear both root and metadata slots and reduce array length. Compiler-managed `pop()` is preferred if generated code demonstrably clears both struct members.
4. On the final pop, `_finalizeCleanup` clears singleton dataset state and pays the deposit exactly as before.
5. Do not delete legacy piece mappings or legacy `nextPieceId`; they are unused and empty in this forward-only prototype.

## Tests

Cover:

- remove a leaf node and an internal Fenwick node;
- lookup remains correct after removal on each side of a piece boundary;
- removed piece is not live and returns zero leaf count;
- removed root is cleared;
- a removed node retains any required partial sum;
- appending after removal uses a new ID rather than filling the hole;
- partial cleanup decrements length by exactly `maxPieces` or remaining count;
- final cleanup clears both slots for every record, clears length/header state, and pays the deposit;
- zero-piece dataset deletion still finalizes immediately.

## Acceptance

- No production code reads, writes, or deletes `pieceCids`, `pieceLeafCounts`, `sumTreeCounts`, or `nextPieceId`.
- Normal removal preserves Fenwick correctness without shrinking the array.
- Cleanup reclaims both compact slots and eventually clears array length.
- Removal and cleanup behavior tests pass.

## Handoff

Record:

- exact metadata write performed for the removed node versus ancestors;
- cleanup clearing mechanism and proof that both struct slots are zeroed;
- targeted test results;
- a repository search result showing legacy piece variables occur only in declarations, layout artifacts, historical comments, or tests awaiting step 7.
