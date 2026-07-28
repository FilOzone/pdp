# Step 8: Run full correctness and layout verification

## Objective

Establish that the compact cutover is behaviorally correct, buildable through the project’s production path, append-only in storage layout, and within contract-size limits before measuring optimization results.

## Prerequisite

Steps 1–7 are complete. Production paths use compact storage and behavior/raw-storage tests are adapted. The old metric characterization may be the only expected failure before step 9.

## Scope

This is a verification and correction step. Fix defects at their source, but do not tune metrics, introduce assembly resizing, or prototype paired metadata.

## Verification order

1. Format check:

   ```sh
   forge fmt --check
   ```

2. Production build:

   ```sh
   make build
   ```

3. Full test suite, excluding only the deliberately stale storage-metric contract if necessary:

   ```sh
   make test
   ```

   If the metric assertions fail, rerun the full suite with only that contract excluded and record the exact exclusion. No other failure may be deferred.

4. Regenerate layout artifacts through the Makefile’s generation path.
5. Confirm generated `PDPVerifierLayout.sol` and `.json` match the source and show only an appended `compactPieces` top-level entry.
6. Run the destructive-layout checker against the branch/base layout. `make check-layout` is the canonical CI command once intended generated changes are part of the checked revision.
7. Run:

   ```sh
   make contract-size-check
   ```

8. Run a repository search proving legacy piece variables have no production references except retained declarations.

## Layout acceptance

- Every pre-existing label, slot, offset, and type remains unchanged.
- `compactPieces` is strictly after the previous maximum slot.
- Its value type is a dynamic array of a two-slot struct ordered `root`, `metadata`.
- Generated Solidity constants and JSON agree.

## Behavioral acceptance

- All non-metric tests pass with `--via-ir` through `make test`.
- Canonical CID malformed-input tests pass.
- Proof, pagination, search, removal, and cleanup scenarios pass end to end.
- Contract-size check passes.
- No legacy fallback or dual write exists.

## Failure handling

Do not weaken assertions to clear a failure. Classify it as one of:

- canonical parsing regression;
- packing corruption/overflow;
- array bounds/default-semantics change;
- Fenwick append/find/remove error;
- cleanup reclamation error;
- generated layout staleness;
- expected old storage-metric mismatch.

Fix all categories except the final metric mismatch before handoff.

## Handoff

Record exact commands, pass/fail counts, compiler warnings, layout checker output, contract-size result, legacy-reference search result, and the sole deferred metric test if one remains. Step 9 must receive a correctness-clean tree, not a partially passing implementation.
