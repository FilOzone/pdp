# Step 2: Add compact storage and packing primitives

## Objective

Append the two-slot `PieceV2` representation and establish tested, centralized metadata packing before any production path writes it.

## Prerequisite

Step 1 is complete: `Cids.validateCommPv2` returns canonical `(padding, height, root)` values and its tests pass.

## Scope

Primary files:

- `src/PDPVerifier.sol`
- a focused test harness/test file following existing test conventions
- generated `src/PDPVerifierLayout.sol`
- generated `src/PDPVerifierLayout.json`

Do not route addition, reads, proofs, or removals to compact storage yet.

## Storage contract

Append after every existing state declaration:

```solidity
struct PieceV2 {
    bytes32 root;
    uint256 metadata;
}

mapping(uint256 setId => PieceV2[] pieces) internal compactPieces;
```

Use the visibility required by test subclasses, but do not expose a new public ABI. Do not remove, retype, reorder, or reuse `pieceCids`, `pieceLeafCounts`, `sumTreeCounts`, or `nextPieceId`. Their declarations are physically retained and become logically unused in later steps.

`PieceV2.root` must be slot 0 and `PieceV2.metadata` slot 1 so array records are contiguous two-slot entries.

## Metadata contract

```text
bits 0..54    padding       55 bits
bits 55..60   height         6 bits
bits 61..111  leaf count    51 bits
bits 112..255 sum-tree     144 bits
```

Add one implementation of each operation:

- pack all fields;
- extract padding;
- extract height;
- extract leaf count;
- extract sum-tree count;
- replace only the sum-tree count;
- clear padding/height/leaf count while preserving the sum.

Solidity does not support `uint55` or `uint51`. Define masks with shifts, for example `(uint256(1) << 55) - 1`; do not use invalid integer types or silent casts.

Packing must reject values larger than their masks. `_withPieceSum` must reject a sum above the 144-bit maximum and preserve every lower bit.

## Tests

Through an existing-style harness, test:

- all-zero round trip;
- independent one-bit values at every field boundary;
- every field maximum;
- combined maxima without overlap;
- one-above-maximum rejection for each field;
- replacing the sum preserves padding, height, and leaf count;
- clearing piece fields preserves the sum and yields leaf count zero;
- `PieceV2` reports two 32-byte storage members in generated layout metadata.

## Generated layout

Regenerate the two layout artifacts after appending the mapping. Confirm the new mapping is appended after the previous maximum slot and the old entries are byte-for-byte structurally unchanged. Full layout validation belongs to step 8, but generated artifacts must remain usable by raw-storage tests in step 7.

## Acceptance

- Packing tests pass.
- The contract builds.
- Generated layout exposes a constant/entry for `compactPieces` and its two-member struct.
- No production path reads or writes `compactPieces` yet.

## Handoff

Record:

- the appended top-level slot number;
- exact struct member order;
- constant names, masks, shifts, helpers, and overflow error;
- the test harness symbols available to later steps;
- generated files changed and commands/results.
