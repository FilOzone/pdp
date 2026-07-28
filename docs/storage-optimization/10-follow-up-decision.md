# Step 10: Decide whether further packing is justified

## Objective

Use the verified measurements—not intuition—to make an explicit go/no-go decision on two optional optimizations: one-shot batch length updates and 1.5-slot paired piece records.

## Prerequisite

Step 9 provides passing 1/4/16/32-piece measurements and a documented compact baseline.

## Scope

This is an analysis and decision step. Update [`../storage-optimization.md`](../storage-optimization.md) with the decision and evidence. Do not implement either optimization unless a separate follow-up task explicitly authorizes it.

## Decision A: one-shot array length update

Quantify:

- repeated array-header reads/writes per batch;
- distinct KAMT objects attributable to the array header;
- theoretical writes saved (`N - 1`) by resizing once;
- whether those writes change KAMT object count or only operation count;
- assembly/storage-layout risk and compiler invariants bypassed.

Default decision: reject unless write-count cost is material in Filecoin execution and a bounded helper can be tested against `push()` semantics. It does not reduce occupied slots and generally modifies the same header object repeatedly.

If recommended, specify a separate prototype with:

- overflow and rollback behavior;
- exactly one length write;
- indexed initialization of every newly exposed element;
- differential tests against ordinary `push()` for multiple batch sizes;
- no delivery as part of the two-slot change.

## Decision B: paired 1.5-slot records

Evaluate a three-slot pair containing two roots and two packed 128-bit metadata records. The proposed per-piece fields are:

```text
padding: 55 bits
height/sentinel: 6 bits
sum-tree count: 67 bits
```

Leaf count is derived. A reserved invalid height marks removed entries while their sum remains present. A 67-bit leaf cap permits just under 4 ZiB per dataset.

Quantify:

- additional slot reduction: two-slot layout to 1.5 slots/piece (25%); legacy five-slot layout to 1.5 (70%);
- KAMT objects touched for paired root/metadata reads;
- read-modify-write coupling between adjacent Fenwick nodes;
- computation added to every leaf-count/liveness read;
- explicit dataset-size semantic change;
- odd piece count, pair initialization, removal, and cleanup complexity;
- proof/read performance compared with interleaved two-slot records.

Default decision: reject unless state footprint remains the dominant measured cost and the 4 ZiB per-dataset cap is explicitly accepted as protocol behavior.

## Output format

Add a decision record containing:

| Candidate | Decision | Measured benefit | Added risk | Follow-up |
|---|---|---|---|---|

For each candidate state one of:

- `adopt in a separate prototype`;
- `defer pending Filecoin cost data`;
- `reject`.

Every benefit claim must cite step 9 output or be marked as a calculated projection. Do not silently turn a projected count into a measured result.

## Acceptance

- Both candidates receive explicit decisions.
- The main document contains the evidence and tradeoff table.
- No production Solidity is changed.
- Any recommended follow-up has a bounded contract, acceptance metrics, and acknowledged semantic changes.

## Handoff

Record the final decisions, evidence table, unresolved external Filecoin pricing/input, documentation diff, and any separately proposed task. This concludes the initial prototype sequence.
