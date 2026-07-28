# Storage metrics comparison

Measured steady-state `addPieces` storage activity for the legacy five-slot representation and the compact two-slot representation. Each case seeds the dataset before recording and then adds the indicated batch.

`Change` is `(compact - legacy) / legacy`. Negative values are reductions.

## Summary

| Batch size | Storage reads | Storage writes | KAMT objects touched | KAMT objects modified | Newly occupied slots |
|---:|---:|---:|---:|---:|---:|
| 1 | 10 → 12 | 7 → 4 | 11 → 7 | 6 → 3 | 5 → 2 |
| 4 | 21 → 25 | 28 → 13 | 24 → 7 | 19 → 3 | 20 → 8 |
| 16 | 69 → 85 | 112 → 49 | 72 → 8 | 67 → 4 | 80 → 32 |
| 32 | 133 → 165 | 224 → 97 | 137 → 9 | 132 → 5 | 160 → 64 |

## Storage reads

| Batch size | Legacy | Compact | Absolute delta | Change |
|---:|---:|---:|---:|---:|
| 1 | 10 | 12 | +2 | +20.0% |
| 4 | 21 | 25 | +4 | +19.0% |
| 16 | 69 | 85 | +16 | +23.2% |
| 32 | 133 | 165 | +32 | +24.1% |

## Storage writes

| Batch size | Legacy | Compact | Writes avoided | Reduction | Legacy / compact |
|---:|---:|---:|---:|---:|---:|
| 1 | 7 | 4 | 3 | 42.9% | 1.75× |
| 4 | 28 | 13 | 15 | 53.6% | 2.15× |
| 16 | 112 | 49 | 63 | 56.2% | 2.29× |
| 32 | 224 | 97 | 127 | 56.7% | 2.31× |

## KAMT objects touched

| Batch size | Legacy | Compact | Objects avoided | Reduction | Legacy / compact |
|---:|---:|---:|---:|---:|---:|
| 1 | 11 | 7 | 4 | 36.4% | 1.57× |
| 4 | 24 | 7 | 17 | 70.8% | 3.43× |
| 16 | 72 | 8 | 64 | 88.9% | 9.00× |
| 32 | 137 | 9 | 128 | 93.4% | 15.22× |

## KAMT objects modified

| Batch size | Legacy | Compact | Objects avoided | Reduction | Legacy / compact |
|---:|---:|---:|---:|---:|---:|
| 1 | 6 | 3 | 3 | 50.0% | 2.00× |
| 4 | 19 | 3 | 16 | 84.2% | 6.33× |
| 16 | 67 | 4 | 63 | 94.0% | 16.75× |
| 32 | 132 | 5 | 127 | 96.2% | 26.40× |

## Newly occupied slots

| Batch size | Legacy | Compact | Slots avoided | Reduction | Legacy / compact |
|---:|---:|---:|---:|---:|---:|
| 1 | 5 | 2 | 3 | 60.0% | 2.50× |
| 4 | 20 | 8 | 12 | 60.0% | 2.50× |
| 16 | 80 | 32 | 48 | 60.0% | 2.50× |
| 32 | 160 | 64 | 96 | 60.0% | 2.50× |

## Observed scaling

| Metric | Legacy | Compact |
|---|---|---|
| Storage writes | `7N` | `3N + 1` |
| Newly occupied slots | `5N` | `2N` |
| KAMT objects modified | Approximately four piece-data objects per piece, plus shared state and occasional CID payload boundary crossings | Two shared objects plus one compact-data object per approximately 16 pieces, subject to initial alignment |

At batch size 32, the compact representation modifies 5 KAMT objects instead of 132, touches 9 instead of 137, and occupies 64 new slots instead of 160. The tradeoff is 165 storage reads instead of 133.
