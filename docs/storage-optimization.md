## Recommendation

Prototype a **two-slot `PieceV2` stored in a per-data-set dynamic array**:

```solidity
struct PieceV2 {
    bytes32 root;
    uint256 metadata;
}

mapping(uint256 setId => PieceV2[] pieces) private compactPieces;
```

Packed metadata:

```text
255                112 111              61 60       55 54          0
+---------------------+-------------------+-----------+-------------+
| sum-tree count: 144 | leaf count: 51    | height: 6 | padding: 55 |
+---------------------+-------------------+-----------+-------------+
```

This implements the two-slot design from [#286](https://github.com/FilOzone/pdp/issues/286), but an array is preferable to `mapping(setId => mapping(pieceId => PieceV2))` because its elements occupy contiguous EVM slots.

With arity-32 KAMT objects:

- Array: approximately 16 two-slot pieces per KAMT object over large batches.
- Nested mapping: approximately one randomly located KAMT object per piece.
- Existing layout: five slots and approximately four KAMT objects per piece during creation.

The current measured four-piece baseline is:

| Metric | Current |
|---|---:|
| Reads | 21 |
| Writes | 28 |
| KAMT objects touched | 24 |
| KAMT objects modified | 19 |
| Newly occupied slots | 20 |

## Compact measurement results

`PDPVerifierStorageTest.testAddPiecesStorageMetrics` creates a fresh dataset for each
batch, adds one seed piece before recording, then records only the measured
`addPieces` call. Values below are measured state-diff counts for the verifier account.

| Pieces | Reads | Writes | KAMT objects touched | KAMT objects modified | Newly occupied slots |
|---:|---:|---:|---:|---:|---:|
| 1 | 12 | 4 | 7 | 3 | 2 |
| 4 | 25 | 13 | 7 | 3 | 8 |
| 16 | 85 | 49 | 8 | 4 | 32 |
| 32 | 165 | 97 | 9 | 5 | 64 |

Every batch satisfies the two-slot invariant: newly occupied slots equal
`2 * pieces`. Against the five-slot legacy representation, the calculated slot
reduction is 3/60% for one piece, 12/60% for four, 48/60% for sixteen, and
96/60% for thirty-two. The four-piece comparison is therefore 20 to 8 slots.

For four pieces, writes change from the legacy baseline's 28 to 13
(-15, calculated 53.6% reduction); touched KAMT objects change from 24 to 7,
and modified objects from 19 to 3. No legacy measurements exist for the other
batch sizes, so this document does not infer corresponding cross-layout changes.

[INFERENCE] Reads and writes scale as `5 * N + 7` and `3 * N + 1`,
respectively, in this compiler/test configuration: fixed dataset and sum-tree
activity contributes the constant component, while each compact record adds its
per-piece component. [INFERENCE] The 16- and 32-piece cases cross contiguous
arity-32 KAMT-slot boundaries: touched/modified object counts rise from 7/3 at
four pieces to 8/4 and 9/5. Those object counts are alignment- and
compiler-dependent characterizations, not portable layout guarantees.

## Available layouts

| Layout | Slots/piece | KAMT locality | Assessment |
|---|---:|---|---|
| Three current mappings | 5 | CID payload partly contiguous; mappings otherwise random | Baseline; remove |
| Nested mapping to `PieceV2` | 2 | Two fields adjacent, records random | Simple but leaves significant KAMT locality on the table |
| Dynamic array of `PieceV2` | 2 | All records contiguous | **Recommended prototype** |
| Custom unstructured contiguous storage | 2 | Contiguous, full control over cursor writes | Potential follow-up; unnecessary assembly risk initially |
| Two pieces sharing one metadata slot | 1.5 | Can be contiguous in three-slot pairs | Aggressive follow-up with semantic limits and higher complexity |

### Why two slots is the safe minimum

The proposed metadata consumes exactly 256 bits:

- padding: 55
- height: 6
- leaf count: 51
- sum-tree count: 144

The root requires another full slot. Removing the cached leaf count only reduces metadata to 205 bits, which still occupies one slot. It also removes the current nonzero leaf-count liveness sentinel and adds arithmetic to hot paths.

### More aggressive 1.5-slot option

Two metadata records could share one slot if we:

- derive leaf count from padding and height,
- use an invalid height value as the deleted-piece sentinel,
- reduce the sum-tree count to 67 bits.

That produces a 128-bit record:

```text
padding 55 + height 6 + sum 67 = 128
```

A 67-bit leaf total still permits just under **4 ZiB per data set**, but this introduces a new explicit dataset-size limit. A three-slot pair could store two roots and their shared metadata.

This would reduce current storage by 70% rather than 60%, but it also:

- couples updates to adjacent Fenwick nodes through read-modify-write,
- complicates odd piece counts and cleanup,
- narrows an existing `uint256` semantic limit,
- increases packing and corruption risk.

Recommendation: implement and measure the two-slot version first. Only prototype paired metadata if two slots remain materially expensive.

## Required contract changes

### 1. Add compact storage without physically replacing old declarations

Even though the prototype will not read legacy pieces, leave slots 2–5 declared and append `compactPieces` after the current storage tail.

This is not behavioral backwards compatibility:

- all piece operations use only `compactPieces`;
- existing legacy values are invisible;
- no cutover marker or fallback routing is added.

It does preserve the upgradeable storage-layout invariant and keeps `make check-layout` useful. Unused mapping declarations consume no KAMT entries.

The array length can become the authoritative next piece ID. The existing `nextPieceId` mapping remains declared but unused.

### 2. Centralize packing

Add helpers for:

- `_packPieceMetadata(padding, height, leafCount, sum)`
- `_piecePadding(metadata)`
- `_pieceHeight(metadata)`
- `_pieceLeafCount(metadata)`
- `_pieceSum(metadata)`
- `_withPieceSum(metadata, sum)`
- `_clearPieceMetadataExceptSum(metadata)`

Required shifts:

```solidity
PADDING_SHIFT = 0;
HEIGHT_SHIFT = 55;
LEAF_COUNT_SHIFT = 61;
SUM_TREE_SHIFT = 112;
```

Packing must define explicit bit masks:

```solidity
PADDING_MAX = (uint256(1) << 55) - 1;
HEIGHT_MAX = (uint256(1) << 6) - 1;
LEAF_COUNT_MAX = (uint256(1) << 51) - 1;
SUM_TREE_MAX = (uint256(1) << 144) - 1;
```

Solidity does not provide `uint55` or `uint51`. Validate every field against its
mask, and also enforce `height <= MAX_PIECE_SIZE_LOG2`. No silent masking or
truncation.

### 3. Fix canonical CID validation first

`Cids.validateCommPv2()` currently accepts extra bytes between the decoded height and the last 32-byte root. `addOnePiece()` reads the height immediately after padding, while proof verification reads the byte before the final root.

Validation needs to establish:

```text
digestOffset + 32 == cid.data.length
```

It should also reject:

- undersized data before indexing the prefix,
- non-minimal/overlong multihash-length uvarints,
- non-minimal/overlong padding uvarints,
- unterminated or overflowing uvarints,
- a declared multihash boundary inconsistent with the canonical digest.

The [FRC-0069 encoding](https://github.com/filecoin-project/FIPs/blob/master/FRCs/frc-0069.md) fixes the final 33 bytes as `height | root`.

Ideally the parser returns all storage components in one pass:

```solidity
(padding, height, root)
```

This avoids validating and then scanning/copying the CID again to extract the root.

### 4. Rewrite addition around one packed write

Current addition in `PDPVerifier.sol:794-810` separately writes:

- sum-tree count,
- dynamic CID header,
- two dynamic CID payload slots,
- leaf count.

The compact path should:

1. Validate and decode the CID.
2. Calculate leaf count.
3. Calculate the new Fenwick sum without writing it separately.
4. Push `PieceV2(root, packedMetadata)` once.
5. Accumulate the batch leaf delta in memory.
6. Update `dataSetLeafCount` once after the loop.

`sumTreeAdd()` should become a calculation returning the new partial sum:

```solidity
function sumTreeSumForAppend(...) internal view returns (uint256 sum);
```

The sum then enters the initial metadata write. This avoids writing the metadata slot twice.

Use ordinary compiler-managed `push()` for the first prototype. It writes the array length for every piece, as the current code does with `nextPieceId++`. A manual one-shot array length update is possible, but should only be considered after measurement because it requires assembly.

### 5. Route every reader through compact accessors

Affected paths in `PDPVerifier.sol`:

- `pieceLive`
- `pieceChallengable`
- `getPieceCid`
- `getPieceLeafCount`
- `getActivePieceCount`
- `getActivePieces`
- `getActivePiecesByCursor`
- `findPieceIdsByCid`
- `schedulePieceDeletions`
- `provePossession`
- `findOnePieceId`
- `findPieceIds`

Boundary behavior:

- `getPieceCid` and pagination reconstruct with `Cids.CommPv2FromDigest`.
- `provePossession` must read root and height directly from `PieceV2`; it should not reconstruct a dynamic CID.
- `findPieceIdsByCid` should decode the query once and compare root, padding, and height directly rather than reconstructing and hashing every stored CID.
- Events and listener callbacks can continue using the original calldata supplied to `addPieces`.

### 6. Rewrite sum-tree updates carefully

All `sumTreeCounts[setId][pieceId]` accesses become metadata reads.

For removal:

1. Load the removed piece’s cached leaf count.
2. Subtract that count from the removed Fenwick node and its ancestors.
3. At the removed piece itself, preserve the resulting sum-tree count but clear padding, height, and leaf count.
4. Delete the root.

The metadata cannot simply be deleted during ordinary removal. A removed Fenwick node may still contain the sum of earlier live pieces covered by that node.

For ancestor nodes, update only the upper 144-bit sum field and preserve their piece metadata.

### 7. Use array length consistently

Replace logical uses of `nextPieceId[setId]` with `compactPieces[setId].length` in:

- bounds checks,
- sum-tree height calculations,
- pagination,
- `getNextPieceId`,
- dataset deletion and cleanup decisions.

Normal piece removal must not shrink the array because piece IDs remain stable and must never be reused.

Dataset cleanup can remove entries from the end with `pop()`, clearing both slots and reducing the length. Existing cleanup permissions and batching remain unchanged.

## Testing work

### CID validation

Add regression cases for:

- extra byte before the root,
- extra byte after the root,
- overlong zero padding encoding,
- overlong multihash length,
- truncated length/padding uvarints,
- valid one- through five-byte padding encodings,
- all existing FRC-0069 vectors.

### Packing invariants

Test round trips at:

- zero,
- each field maximum,
- adjacent-bit boundaries,
- maximum valid height and leaf count,
- maximum 144-bit sum,
- overflow rejection.

### Contract behavior

Existing tests must continue covering:

- exact CID round trip through `getPieceCid`,
- pagination,
- CID lookup,
- liveness,
- scheduled removal,
- proving against the stored root and height,
- Fenwick lookup after removing pieces,
- add-after-removal without ID reuse,
- incremental dataset cleanup.

`test/CleanupPieces.t.sol` currently inspects the five legacy slots directly and must be rewritten for compact array slots.

The test subclass exposing `sumTreeCounts` must instead expose the packed sum accessor.

### Storage metrics

Update `PDPVerifierStorage.t.sol` only after implementation measurements.

Hard acceptance criterion for four pieces:

```text
new occupied slots: 8
```

Also add a larger batch—preferably 32 pieces—to demonstrate array locality across KAMT boundaries. A four-piece test alone can produce deceptively favorable or unfavorable results depending on the array base-slot alignment.

Suggested measured scenarios:

- 1 piece: fixed overhead
- 4 pieces: comparison with current baseline
- 16 pieces: one logical 32-slot record group
- 32 pieces: crosses at least one KAMT boundary

Do not preselect assertions for reads, writes, or KAMT objects; record the implemented results first, then establish the new characterization baseline.

## Proposed prototype sequence

1. Harden canonical PieceCIDv2 decoding.
2. Add `PieceV2`, packing helpers, and compact array at the storage tail.
3. Convert addition and Fenwick append calculation.
4. Convert proof and lookup hot paths.
5. Convert getters, pagination, and CID search.
6. Convert normal removal and cleanup.
7. Adapt behavioral and raw-storage tests.
8. Run the full suite and storage-layout checks.
9. Measure 1/4/16/32-piece storage activity.
10. Decide from measurements whether batch-length assembly or 1.5-slot paired metadata is justified.

No cutover marker, legacy reads, legacy deletes, or migration logic should be part of this prototype.

## Execution digests

Sequential, agent-ready handoffs for this prototype are indexed in
[`storage-optimization/README.md`](storage-optimization/README.md).
