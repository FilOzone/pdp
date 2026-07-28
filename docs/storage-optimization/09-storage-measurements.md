# Step 9: Measure compact storage at 1, 4, 16, and 32 pieces

## Objective

Replace the legacy four-piece characterization with measured compact results and demonstrate both the two-slot invariant and contiguous KAMT locality across batch sizes.

## Prerequisite

Step 8 proves correctness, append-only layout safety, and contract-size compliance. Do not measure a tree with unresolved behavioral failures.

## Scope

Primary files:

- `test/PDPVerifierStorage.t.sol`
- [`../storage-optimization.md`](../storage-optimization.md) for recording final compact results

Do not alter production code to improve measurements in this step.

## Measurement design

For each batch size `N` in `1, 4, 16, 32`:

1. Create a fresh dataset.
2. Add one seed piece before recording so the compact array header and shared dataset counters are already occupied.
3. Build `N` canonical pieces with deterministic, distinct roots and valid heights/padding.
4. Record only `addPieces` using Foundry state-diff recording.
5. Calculate the existing five metrics for the verifier account:
   - storage reads;
   - storage writes;
   - distinct arity-32 KAMT objects touched (`slot >> 5`);
   - distinct KAMT objects modified;
   - newly occupied slots based on first previous and final values per written slot.
6. Keep deduplication over slots/objects; repeated writes must count as writes but not as additional distinct objects or newly occupied slots.

Use isolated datasets or state snapshots so one scenario cannot influence another’s header occupancy or slot alignment.

## Assertions

Hard semantic assertion:

```text
newly occupied slots == 2 * N
```

This must hold for every scenario. If it does not, inspect array-header seeding, duplicate roots that encode zero, or unexpected production storage before changing the assertion.

For reads, writes, and KAMT objects:

1. Run and record actual values first.
2. Explain fixed versus per-piece components.
3. Establish exact characterization assertions only after results are observed.
4. Do not insert the earlier estimate of 3–4 modified objects as an expected value.

The 16/32-piece cases must show the effect of contiguous records across a 32-slot KAMT boundary; report actual alignment-dependent object counts.

## Documentation update

Preserve the legacy four-piece baseline in the main document and add a compact-results table. State:

- absolute and percentage slot reduction;
- write-count change;
- touched/modified object change;
- batch-size scaling;
- any metric whose interpretation is compiler- or alignment-dependent.

Mark calculated interpretations as such; measured values need no inference label.

## Acceptance

- All four metric scenarios pass.
- Four pieces create exactly eight new slots, a 60% reduction from 20.
- Thirty-two pieces create exactly 64 new slots.
- `forge test --match-contract PDPVerifierStorageTest -vv` prints and asserts the measured values.
- The full suite passes with the updated characterization.

## Handoff

Record raw output for every scenario, the final assertion table, storage reduction calculations, KAMT alignment observations, documentation changes, and confirmation that production code was untouched.
