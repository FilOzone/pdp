# Step 1: Harden canonical PieceCIDv2 decoding

## Objective

Make `Cids` produce one trustworthy `(padding, height, root)` tuple and reject every encoding that could make storage and proof verification interpret different bytes.

## Prerequisites

- Read [`../storage-optimization.md`](../storage-optimization.md), especially “Fix canonical CID validation first”.
- Read FRC-0069’s digest definition: `uvarint padding | uint8 height | 32 byte root`.
- Inspect `src/Cids.sol` and `test/Cids.t.sol`; do not rely on historical line numbers.

## Scope

Primary files:

- `src/Cids.sol`
- `test/Cids.t.sol`
- Call sites whose tuple destructuring must change to keep the tree compiling

Do not add compact storage or change PDP piece behavior in this step.

## Required change

1. Change the canonical validator contract to return the decoded root directly:

   ```solidity
   function validateCommPv2(Cid memory cid)
       internal
       pure
       returns (uint256 padding, uint8 height, bytes32 root);
   ```

   Migrate all tuple destructuring in the repository. Do not leave a second decoder or compatibility wrapper.

2. Validate minimum length before indexing the four-byte prefix.
3. Decode both the multihash length and padding uvarints with explicit bounds checks.
4. Reject unterminated uvarints and values that overflow `uint256`.
5. Require minimal uvarint encodings. The bytes consumed must equal `_uvarintLength(decodedValue)`.
6. Require the declared multihash length to end exactly at `cid.data.length`.
7. After padding and height are decoded, require exactly 32 bytes to remain:

   ```text
   rootOffset + 32 == cid.data.length
   ```

8. Load the root at that validated offset. Avoid allocating and byte-copying a temporary 32-byte array.
9. Keep `CommPv2FromDigest` as the canonical reconstruction function.

## Tests

Add deterministic cases for:

- valid FRC-0069 vectors;
- valid padding uvarints at one- through five-byte boundaries;
- data shorter than the prefix/minimum CID;
- an extra byte between height and root;
- an extra byte after the root;
- overlong zero encodings for multihash length and padding;
- truncated multihash-length and padding uvarints;
- a declared multihash length smaller or larger than the actual payload;
- a uvarint that exceeds `uint256`.

Existing `_readUvarint` round-trip coverage, including `type(uint256).max`, must continue to pass.

## Acceptance

- Canonical vectors return the exact padding, height, and root.
- The added malformed inputs revert before any caller can persist them.
- No caller derives height from one location and root from an independently assumed location.
- `forge test --match-contract CidsTest -vv` passes.
- A repository build succeeds after tuple call sites are migrated.

## Handoff

Record:

- the final validator signature;
- whether root loading uses assembly and the exact validated pointer invariant;
- errors/revert strings introduced;
- targeted test and build results;
- any downstream call site that still extracts CID components separately.
