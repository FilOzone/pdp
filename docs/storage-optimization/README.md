# Storage optimization execution digests

These digests split the prototype sequence in [`../storage-optimization.md`](../storage-optimization.md) into sequential handoffs. Each digest is scoped so a fresh agent can start from the previous step's completed tree without needing the previous agent's conversation.

## Working contract

- Execute the files in numeric order.
- Start by reading the main recommendation, the current digest, and the immediately preceding digest's handoff section.
- Inspect the current code before editing; line numbers in the main document are orientation only.
- Keep the prototype forward-only: compact storage is authoritative and there is no legacy read, write, delete, cutover, or migration path.
- Preserve the existing upgradeable layout physically: old declarations remain, and new state is appended.
- Do not begin later steps to make an intermediate full-suite failure disappear. Each digest names the validation expected at that boundary.
- End each step with a handoff containing changed files, relevant symbol/API decisions, commands run, results, and known failures intentionally deferred to later steps.

## Sequence

1. [`01-canonical-cid-decoding.md`](01-canonical-cid-decoding.md)
2. [`02-compact-storage-and-packing.md`](02-compact-storage-and-packing.md)
3. [`03-addition-and-fenwick-append.md`](03-addition-and-fenwick-append.md)
4. [`04-proof-and-lookup-hot-paths.md`](04-proof-and-lookup-hot-paths.md)
5. [`05-getters-pagination-and-cid-search.md`](05-getters-pagination-and-cid-search.md)
6. [`06-removal-and-cleanup.md`](06-removal-and-cleanup.md)
7. [`07-adapt-tests.md`](07-adapt-tests.md)
8. [`08-full-verification.md`](08-full-verification.md)
9. [`09-storage-measurements.md`](09-storage-measurements.md)
10. [`10-follow-up-decision.md`](10-follow-up-decision.md)

## Shared invariants

- `PieceV2` occupies exactly two adjacent storage slots: root, then packed metadata.
- Metadata layout is `padding[0:54]`, `height[55:60]`, `leafCount[61:111]`, `sumTreeCount[112:255]`.
- `compactPieces[setId].length` is the next piece ID and only shrinks during dataset cleanup.
- A live piece has a nonzero packed leaf count.
- Ordinary removal clears the root and piece fields but preserves the updated Fenwick sum.
- Dataset cleanup clears both slots and reduces the array length.
- Public CID-returning boundaries reconstruct canonical PieceCIDv2 values; proof verification consumes root and height directly.
- Four steady-state additions create exactly eight newly occupied piece slots.
