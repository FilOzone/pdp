# Step 7: Adapt behavioral and raw-storage tests

## Objective

Remove test dependence on the five-slot legacy representation and make the existing suite defend compact behavior, packing, Fenwick semantics, and cleanup reclamation.

## Prerequisite

Steps 1–6 complete the production cutover. Legacy piece variables remain declared for layout safety but are unused by production code.

## Scope

Expected files include:

- `test/Cids.t.sol`
- `test/PDPVerifier.t.sol`
- `test/PDPVerifierProofTest.t.sol`
- `test/CleanupPieces.t.sol`
- focused packing/addition tests added earlier
- `src/PDPVerifierLayout.sol` if raw-slot constants need regeneration

Do not update the storage-metric baseline in this step; that is step 9 after full correctness verification.

## Required adaptations

1. Replace test harness access to `sumTreeCounts` with the production compact sum accessor or a thin internal harness exposure.
2. Replace raw cleanup assertions for CID header/payload, leaf mapping, and sum mapping with compact array assertions.
3. Derive compact slots from generated layout constants rather than hardcoding the top-level slot:

   ```text
   arrayHeader = keccak256(abi.encode(setId, COMPACT_PIECES_SLOT))
   elementsBase = keccak256(abi.encodePacked(arrayHeader))
   rootSlot(id) = elementsBase + 2 * id
   metadataSlot(id) = rootSlot(id) + 1
   ```

4. Assert that final cleanup clears root, metadata, and the dynamic-array length/header.
5. Preserve tests for exact external behavior rather than replacing them with internal packing assertions.
6. Remove comments and helper names that describe the legacy five-slot invariant.
7. Keep legacy storage declarations/layout constants covered only as upgrade-layout history; do not assert new writes to them.

## Required behavioral coverage

The combined suite must defend:

- canonical CID rejection and round trip;
- packing boundaries and overflow;
- first and subsequent piece IDs;
- exact getter CID bytes and leaf counts;
- active pagination and CID search;
- scheduled removal rules;
- proof verification from compact root/height;
- Fenwick lookup before and after removals;
- holes and no ID reuse;
- partial and final cleanup;
- raw reclamation of both compact slots.

Every new test must fail under a plausible packing, sum-preservation, array-length, or cleanup bug. Avoid source-text assertions and tests that only restate helper implementation.

## Acceptance

- All behavior-focused test contracts pass under their normal non-`via-ir` invocation.
- Cleanup raw-slot tests prove both slots and the array header are zero after final cleanup.
- No test reads legacy piece mappings as the source of truth.
- Storage metric assertions remain at the old baseline temporarily and are excluded from this step’s all-test claim if they now fail as expected.

## Handoff

Record:

- tests and helpers removed/rewritten;
- raw slot derivation used and generated constant name;
- targeted suite results;
- the exact remaining failure list, expected to contain only the old storage-metric characterization if applicable.
