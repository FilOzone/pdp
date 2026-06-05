# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Fixed
- `cleanupPieces()` now uses the same permission gate as `deleteDataSet()`, anchored to last proving activity instead of cleanup-mode entry. The abandonment path previously required two full `INACTIVITY_WINDOW` periods (~60 days); a permissionless deleter can now clean up and collect the deposit immediately. An SP deleting after exceeding the inactivity window no longer gets an exclusive cleanup period (the data set was already permissionlessly deletable). The unused `cleanupModeEpoch` storage is deprecated in place.

## [3.4.0] - 2026-05-28

This release upgrades the deployed PDPVerifier contract with data-set cleanup deposits and explicit piece-cleanup finalization. New data sets now hold a 0.1 FIL cleanup deposit that is returned to whoever completes cleanup after deletion, giving storage providers and permissionless cleanup callers a concrete incentive to clear on-chain piece state.

The active Mainnet and Calibnet proxies now report `VERSION() == "3.4.0"`. The `v3.3.0` release was library-only and did not deploy a PDPVerifier implementation, so this rollout intentionally fast-forwards the deployed contract version from `3.2.0` to `3.4.0`.

### Deployed

The implementation contracts were deployed from commit [`1370f49f9af958e4e3a1396377035685d55ffdba`](https://github.com/FilOzone/pdp/commit/1370f49f9af958e4e3a1396377035685d55ffdba). The `v3.4.0` release tag may point to a later documentation-only commit that finalizes these release notes.

**Mainnet:**
- PDPVerifier Implementation: [0xb41A97FEDD2D9497C639A643ec75E56CbCeDe8BA](https://filecoin.blockscout.com/address/0xb41A97FEDD2D9497C639A643ec75E56CbCeDe8BA?tab=contract)
- PDPVerifier Proxy: [0xBADd0B92C1c71d02E7d520f64c0876538fa2557F](https://filecoin.blockscout.com/address/0xBADd0B92C1c71d02E7d520f64c0876538fa2557F?tab=contract)
- Proxy Upgrade Transaction: [0x07407b3becb1786e3b4217bfb5774d155d91d9688b0800fe5740689a72c4ed10](https://filecoin.blockscout.com/tx/0x07407b3becb1786e3b4217bfb5774d155d91d9688b0800fe5740689a72c4ed10)

**Calibnet:**
- PDPVerifier Implementation: [0xd60b90f6D3C42B26a246E141ec701a20Dde2fA61](https://filecoin-testnet.blockscout.com/address/0xd60b90f6D3C42B26a246E141ec701a20Dde2fA61?tab=contract)
- PDPVerifier Proxy: [0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C](https://filecoin-testnet.blockscout.com/address/0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C?tab=contract)
- Proxy Upgrade Transaction: [0x0bb3597820f0c14a902f6c5672e5b3d1e2f9b7e60174773af07ef6f2762121ad](https://filecoin-testnet.blockscout.com/tx/0x0bb3597820f0c14a902f6c5672e5b3d1e2f9b7e60174773af07ef6f2762121ad)

### Breaking Changes
- New data-set creation now requires a 0.1 FIL cleanup deposit. Callers of `createDataSet()` and callers that create a data set through `addPieces(NEW_DATA_SET_SENTINEL, ...)` must send at least `FIL_CLEANUP_DEPOSIT()` in `msg.value`; excess FIL is refunded.
- The previous USDFC sybil-fee payment path has been removed from PDPVerifier. Integrations should use the FIL cleanup deposit flow instead of relying on USDFC sybil-fee payment getters or payment-contract constructor values.
- PDPVerifier implementation deployment now uses constructor args `(uint64 initializerVersion, uint256 challengeFinality)`. For this rollout, use `initializerVersion = 3`, `challengeFinality = 10` on Calibration, and `challengeFinality = 150` on Mainnet.
- Several data-set liveness failures now revert with custom errors such as `DataSetNotLive()` and `DataSetNotFound()` instead of string revert reasons. Integrations that decode revert data should update their expectations ([#274](https://github.com/FilOzone/pdp/pull/274)).

### Added
- Added a per-data-set cleanup deposit that is collected when a data set is created and paid to the caller who completes cleanup ([#270](https://github.com/FilOzone/pdp/pull/270)).
- Added `cleanupPieces(setId, maxPieces)` so deleted data sets with remaining pieces can be cleaned incrementally, clearing piece CID, leaf-count, and sum-tree storage before finalizing deletion ([#270](https://github.com/FilOzone/pdp/pull/270)).
- Added `FIL_CLEANUP_DEPOSIT()` to expose the current cleanup deposit amount to typed integrations ([#270](https://github.com/FilOzone/pdp/pull/270)).
- Added permissionless deletion and cleanup paths after `INACTIVITY_WINDOW`, while keeping cleanup provider-restricted during the inactivity window ([#270](https://github.com/FilOzone/pdp/pull/270)).

### Changed
- Moved `challengeFinality` from proxy storage into an immutable implementation constructor value while preserving `getChallengeFinality()` for callers ([#270](https://github.com/FilOzone/pdp/pull/270)).
- Updated PDPVerifier deploy and upgrade tooling for the new constructor shape and network-specific challenge finality values ([#270](https://github.com/FilOzone/pdp/pull/270)).
- Kept `getNextPieceId()` and `getNextChallengeEpoch()` readable while a data set is in cleanup mode, allowing cleanup and indexing callers to inspect teardown state after deletion starts ([#274](https://github.com/FilOzone/pdp/pull/274)).

### Maintenance
- Regenerated PDPVerifier storage layout files and updated storage-layout checks to support intentional deprecated-slot renames ([#270](https://github.com/FilOzone/pdp/pull/270)).
- Added cleanup-focused tests covering incremental cleanup, zero-piece data sets, permissionless cleanup after inactivity, deposit payout timing, and storage-slot clearing ([#270](https://github.com/FilOzone/pdp/pull/270)).
- Removed redundant data-set bounds checks now covered by storage-provider liveness checks, with tests updated for the custom-error revert shape ([#274](https://github.com/FilOzone/pdp/pull/274)).

## [3.3.0] - 2026-05-07

This release updates the PDP Solidity library with raw-size helper functions for PieceCIDv2 values. `Cids.rawPieceSize(padding, height)` derives the exact original raw byte size from FRC-0069 padding and tree height, while `Cids.leafCountToRawSize(leaves)` converts aggregate data-bearing leaf counts into raw byte estimates for callers that already work with PDP leaf totals. These helpers are useful for indexers, services, and integrations that need to recover or report user-data sizes from piece metadata without reimplementing the PieceCID sizing math.

No PDPVerifier contract upgrade is included in `v3.3.0`; the [deployed Mainnet and Calibnet PDPVerifier contracts remain the `v3.2.0` deployments](https://github.com/FilOzone/pdp/releases/tag/v3.2.0). Integrations that only call the deployed contracts do not need to take action.

### Deployed

No new deployments in this release. The active PDPVerifier addresses remain:

**Mainnet:**
- PDPVerifier Implementation: [0xC57535dfaF5da0537cBf886313965Cf76b82C24E](https://filecoin.blockscout.com/address/0xC57535dfaF5da0537cBf886313965Cf76b82C24E?tab=contract)
- PDPVerifier Proxy: [0xBADd0B92C1c71d02E7d520f64c0876538fa2557F](https://filecoin.blockscout.com/address/0xBADd0B92C1c71d02E7d520f64c0876538fa2557F?tab=contract)

**Calibnet:**
- PDPVerifier Implementation: [0x4c8eDFD417D5dAb87F24905321fC5C5e6d38A6E9](https://filecoin-testnet.blockscout.com/address/0x4c8eDFD417D5dAb87F24905321fC5C5e6d38A6E9?tab=contract)
- PDPVerifier Proxy: [0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C](https://filecoin-testnet.blockscout.com/address/0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C?tab=contract)

### Breaking Changes
- None. There are no changes to the deployed PDPVerifier contract API or behavior.

### Added
- Added raw-size helpers to the `Cids` library: `rawPieceSize(padding, height)` for exact per-piece raw sizes and `leafCountToRawSize(leaves)` for aggregate leaf-count estimates, with unit coverage for both behaviors ([#266](https://github.com/FilOzone/pdp/pull/266))

### Maintenance
- Added additive-only PDPVerifier storage layout generation and CI checks to reduce risk in future contract upgrades ([#263](https://github.com/FilOzone/pdp/pull/263))
- Added a PDPVerifier upgrade checklist issue template for future rollouts ([#260](https://github.com/FilOzone/pdp/pull/260))

## [3.2.0] - 2026-03-19

This release upgrades PDPVerifier from `v3.1.0` to `v3.2.0` and adds better piece discovery APIs plus support for satisfying sybil-fee requirements via USDFC-backed payments. The existing FIL-based fee path remains supported.

### Deployed

**Mainnet:**
- PDPVerifier Implementation: [0xC57535dfaF5da0537cBf886313965Cf76b82C24E](https://filecoin.blockscout.com/address/0xC57535dfaF5da0537cBf886313965Cf76b82C24E?tab=contract)
- PDPVerifier Proxy: [0xBADd0B92C1c71d02E7d520f64c0876538fa2557F](https://filecoin.blockscout.com/address/0xBADd0B92C1c71d02E7d520f64c0876538fa2557F?tab=contract)

**Calibnet:**
- PDPVerifier Implementation: [0x4c8eDFD417D5dAb87F24905321fC5C5e6d38A6E9](https://filecoin-testnet.blockscout.com/address/0x4c8eDFD417D5dAb87F24905321fC5C5e6d38A6E9?tab=contract)
- PDPVerifier Proxy: [0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C](https://filecoin-testnet.blockscout.com/address/0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C?tab=contract)

### Breaking Changes
- No breaking changes for existing PDP user flows such as dataset creation, piece management, proof submission, or the existing read/query methods used against `v3.1.0`.

### Added
- Added `getActivePiecesByCursor()` for cursor-based pagination, allowing clients to page through large data sets in `O(limit)` gas instead of paying the `O(offset)` scan cost of `getActivePieces()` ([#246](https://github.com/FilOzone/pdp/pull/246))
- Added `findPieceIdsByCid()` to look up active piece IDs by piece CID with cursor-style scanning and bounded result size ([#250](https://github.com/FilOzone/pdp/pull/250))
- Added support for satisfying sybil-fee requirements for `createDataSet()` and the new-data-set path of `addPieces()` via USDFC-backed payments, with FIL burn fallback when `msg.value` is provided ([#249](https://github.com/FilOzone/pdp/pull/249))
- Added the `USDFC_SYBIL_FEE()` getter to `IPDPVerifier` so typed integrations can read the configured USDFC sybil-fee amount ([#249](https://github.com/FilOzone/pdp/pull/249))
- Added the `FIL_SYBIL_FEE()` getter to `IPDPVerifier` so integrations can read the FIL fallback sybil-fee amount directly from the contract ([#256](https://github.com/FilOzone/pdp/pull/256))
  - Impact on existing `PDPListener` integrations: none. Listener callbacks and emitted events are unchanged, so existing listeners continue to work without modification unless they want to query the new getter.

### Changed
- Updated `provePossession()` to follow check-effects-interactions ordering by recording the proven epoch before external listener callbacks and refunds ([#242](https://github.com/FilOzone/pdp/pull/242))

### Documentation
- Added a per-piece security guarantees section to the design documentation to clarify the probabilistic protection model for data-set proving ([#241](https://github.com/FilOzone/pdp/pull/241))

## [3.1.0] - 2025-10-27

This release addresses an issue discovered during end-to-end testing of PDP v3.0.0. The `schedulePieceDeletions()` function lacked duplicate piece ID validation, which could lead to unexpected behavior when the same piece ID was scheduled for removal multiple times.

The issue has been resolved with bitmap-based duplicate detection, and these contracts will be used for the GA release.

### Deployed

**Mainnet:**
- PDPVerifier Implementation: [0xe2Dc211BffcA499761570E04e8143Be2BA66095f](https://filfox.info/en/address/0xe2Dc211BffcA499761570E04e8143Be2BA66095f)
- PDPVerifier Proxy: [0xBADd0B92C1c71d02E7d520f64c0876538fa2557F](https://filfox.info/en/address/0xBADd0B92C1c71d02E7d520f64c0876538fa2557F)

**Calibnet:**
- PDPVerifier Implementation: [0x2355Cb19BA1eFF51673562E1a5fc5eE292AF9D42](https://calibration.filfox.info/en/address/0x2355Cb19BA1eFF51673562E1a5fc5eE292AF9D42)
- PDPVerifier Proxy: [0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C](https://calibration.filfox.info/en/address/0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C)

### Added
- Prevent duplicate piece IDs in schedulePieceDeletions ([#228](https://github.com/FilOzone/pdp/pull/228))
  - Added two-level bitmap tracking for unlimited piece ID support in scheduled removals
  - Prevents duplicate piece IDs from being added to scheduled deletion queue
  - Enhanced validation to only allow live pieces to be scheduled for removal

## [3.0.0] - 2025-10-21

### Deployed

**Mainnet:**
- PDPVerifier Implementation: [[0x78d8C130995701136EeC85094628015967315FB8](https://filfox.info/en/address/0x78d8C130995701136EeC85094628015967315FB8)
- PDPVerifier Proxy: [0x8b3e727D1Df709D5cac9FcBef57B139A9298766C](https://filfox.info/en/address/0x8b3e727D1Df709D5cac9FcBef57B139A9298766C)

**Calibnet:**
- PDPVerifier Implementation: [0x9Fe814dd4eC663557c3D74c386CB5BC4be528Dd1](https://calibration.filfox.info/en/address/0x9Fe814dd4eC663557c3D74c386CB5BC4be528Dd1)
- PDPVerifier Proxy: [0x06279D540BDCd6CA33B073cEAeA1425B6C68c93d](https://calibration.filfox.info/en/address/0x06279D540BDCd6CA33B073cEAeA1425B6C68c93d)

### 💥 Breaking Changes
- **BREAKING**: Changed `getActivePieces()` return signature ([#223](https://github.com/FilOzone/pdp/pull/223))
  - **Removed**: `rawSizes` array from return values
  - **Before**: `returns (Cids.Cid[] memory pieces, uint256[] memory pieceIds, uint256[] memory rawSizes, bool hasMore)`
  - **After**: `returns (Cids.Cid[] memory pieces, uint256[] memory pieceIds, bool hasMore)`
  - **Migration Guide**: Remove any code that expects or uses the `rawSizes` return value from `getActivePieces()`. The raw size information was redundant as it can be derived from the piece CIDs themselves.

### Changed
- Removed `EXTRA_DATA_MAX_SIZE` limit (previously 2048 bytes) allowing unlimited extra data in function calls ([#225](https://github.com/FilOzone/pdp/pull/225))
- Clarified naming: renamed `rawSize` parameter to `proofSize` in `calculateProofFeeForSize()` for better clarity ([#223](https://github.com/FilOzone/pdp/pull/223))

### Removed  
- Removed internal `calculateCallDataSize()` function and `gasUsed` calculation logic ([#222](https://github.com/FilOzone/pdp/pull/222)) 

## [2.2.1] - 2025-10-08

### Deployed

**Mainnet:**
- PDPVerifier Implementation: [0xbeeD1aea4167787D0CA6d8989B9C7594749215AE](https://filfox.info/en/address/0xbeeD1aea4167787D0CA6d8989B9C7594749215AE)
- PDPVerifier Proxy: [0x255cd1BFE3A83889607b8A7323709b24657d3534](https://filfox.info/en/address/0x255cd1BFE3A83889607b8A7323709b24657d3534)

**Calibnet:**
- PDPVerifier Implementation: [0x4EC9a8ae6e6A419056b6C332509deEA371b182EF](https://calibration.filfox.info/en/address/0x4EC9a8ae6e6A419056b6C332509deEA371b182EF)
- PDPVerifier Proxy: [0x579dD9E561D4Cd1776CF3e52E598616E77D5FBcb](https://calibration.filfox.info/en/address/0x579dD9E561D4Cd1776CF3e52E598616E77D5FBcb/)

### Added

- Restored `createDataSet()` function for enhanced flexibility in dataset initialization, enabling empty "bucket" creation, smoother Curio integration workflows, and synapse-sdk integration ([#219](https://github.com/FilOzone/pdp/pull/219))
- Implemented FVM precompiles for native payments, burn operations, and beacon randomness functionality ([#207](https://github.com/FilOzone/pdp/pull/207))

## [2.2.0] - 2025-10-06

### Deployed

**Mainnet:**
- PDPVerifier Implementation: [[0xfEFD001a9aFfb38Bba7f81e3FB37a1ab8F392A5A](https://filfox.info/en/address/0xfEFD001a9aFfb38Bba7f81e3FB37a1ab8F392A5A)
- PDPVerifier Proxy: [0x9F1bc521A7C3cFeC76c32611Aab50a6dFfb93290](https://filfox.info/en/address/0x9F1bc521A7C3cFeC76c32611Aab50a6dFfb93290)

**Calibnet:**
- PDPVerifier Implementation: [0xCa92b746a7af215e0AaC7D0F956d74B522b295b6](https://calibration.filfox.info/en/address/0xCa92b746a7af215e0AaC7D0F956d74B522b295b6)
- PDPVerifier Proxy: [0x9ecb84bB617a6Fd9911553bE12502a1B091CdfD8](https://calibration.filfox.info/en/address/0x9ecb84bB617a6Fd9911553bE12502a1B091CdfD8)

### 💥 Breaking Changes
- Merged `createDataset` and `addPieces` functions for streamlined dataset creation ([#201](https://github.com/FilOzone/pdp/pull/201))
  - **Removed**: `createDataset()` function no longer exists
  - **Changed**: `addPieces()` now handles both creating new datasets AND adding pieces to existing datasets
  - **Migration Guide**:
    - To create a new dataset with pieces: Call `addPieces(type(uint256).max, listenerAddress, pieces, extraData)`
    - To add pieces to existing dataset: Call `addPieces(datasetID, address(0), pieces, extraData)`
  - **Benefits**: Single transaction replaces the previous two-step process (create, then add), reducing wait times and gas costs

### Added
- feat: Update PDP proof fee ([#214](https://github.com/FilOzone/pdp/pull/214))

### Changed
- rm unused constants ([#211](https://github.com/FilOzone/pdp/pull/211))
- remove seconds per day again ([#215](https://github.com/FilOzone/pdp/pull/215))
- Fixed `vm.getBlockNumber` in test environments ([#206](https://github.com/FilOzone/pdp/pull/206))

### 📝 Changelog

For the full set of changes since the last tag:

**[View all changes between v2.1.0 and v2.2.0-rc1](https://github.com/FilOzone/pdp/compare/v2.1.0...v2.2.0-rc1)**

## [2.1.0] - 2025-09-17

### Deployed

**Mainnet:**
- PDPVerifier Implementation: [0xf2a47b4136Ab2dfB6FA67Fb85c7a031f56F6f024](https://filfox.info/en/address/0xf2a47b4136Ab2dfB6FA67Fb85c7a031f56F6f024)
- PDPVerifier Proxy: [0x31D87004Fc0C38D897725978e51BC06163603E5A](https://filfox.info/en/address/0x31D87004Fc0C38D897725978e51BC06163603E5A)

**Calibnet:**
- PDPVerifier Implementation: [0x648E8D9103Ec91542DcD0045A65Ef9679F886e82](https://calibration.filfox.info/en/address/0x648E8D9103Ec91542DcD0045A65Ef9679F886e82)
- PDPVerifier Proxy: [0x445238Eca6c6aB8Dff1Aa6087d9c05734D22f137](https://calibration.filfox.info/en/address/0x445238Eca6c6aB8Dff1Aa6087d9c05734D22f137)

### 💥 Breaking Changes
- **BREAKING**: Switched from Piece CID version 1 to version 2 ([#184](https://github.com/FilOzone/pdp/pull/184))
  - New `Cids.sol` library with CIDv2 handling capabilities
  - **No backward compatibility** - CIDv1 support completely removed
  - Enhanced piece data validation using CID height information
  - Golden tests for CommPv2 functionality

### 🚀 Added
- **Data Set Indexing**: Data set IDs now start at 1 instead of 0 ([#196](https://github.com/FilOzone/pdp/pull/196))
- **Event Enhancement**: Added `root_cids` to `RootsAdded` event for better piece tracking ([#169](https://github.com/FilOzone/pdp/pull/169))

### 🔧 Changed
- **Interface Updates**: IPDPProvingSchedule methods changed from `pure` to `view` for accurate state access patterns ([#186](https://github.com/FilOzone/pdp/pull/186))
- **Price Validation**: Updated price validation logic to accept older price data for improved reliability ([#191](https://github.com/FilOzone/pdp/pull/191))
- **Performance Optimization**: Reduced optimizer runs to minimize deployed contract size ([#194](https://github.com/FilOzone/pdp/pull/194))
- **Code Architecture**: Transitioned from `IPDPTypes.PieceData` to `Cids.Cid` throughout the codebase for better type consistency ([#184](https://github.com/FilOzone/pdp/pull/184))
- **Code Quality**: Comprehensive formatting improvements across all Solidity files and tests ([#185](https://github.com/FilOzone/pdp/pull/185))
- **Documentation**: Updated README to point to latest release ([#192](https://github.com/FilOzone/pdp/pull/192))

### 🐛 Fixed
- Various test stability improvements and bug fixes
- Enhanced error handling in CID processing
- Improved code formatting consistency

### 📝 Changelog

For the set of changes since the last tag:

**[View all changes between v2.0.0 and v2.1.0](https://github.com/FilOzone/pdp/compare/v2.0.0...v2.1.0)**

## [2.0.0] - 2025-07-20
### Changed
- **BREAKING**: Renamed core terminology throughout the codebase for better clarity, for each of the following, all functions, variables, events, and parameters have been changed.
  - `proofSet` → `dataSet` ("proof set" becomes "data set")
  - `root` → `piece`
  - `rootId` → `pieceId`
  - `owner` → `storageProvider`
  - Function renames:
    - `createProofSet()` → `createDataSet()`
    - `deleteProofSet()` → `deleteDataSet()`
    - `getNextProofSetId()` → `getNextDataSetId()`
    - `proofSetLive()` → `dataSetLive()`
    - `getProofSetLeafCount()` → `getDataSetLeafCount()`
    - `getProofSetListener()` → `getDataSetListener()`
    - `getProofSetLastProvenEpoch()` → `getDataSetLastProvenEpoch()`
    - `getProofSetOwner()` → `getDataSetStorageProvider()`
    - `proposeProofSetOwner()` → `proposeDataSetStorageProvider()`
    - `claimProofSetOwnership()` → `claimDataSetStorageProvider()`
    - `addRoots()` → `addPieces()`
    - `getNextRootId()` → `getNextPieceId()`
    - `rootLive()` → `pieceLive()`
    - `rootChallengable()` → `pieceChallengable()`
    - `getRootCid()` → `getPieceCid()`
    - `getRootLeafCount()` → `getPieceLeafCount()`
    - `findRootIds()` → `findPieceIds()`
    - `scheduleRemovals()` → `schedulePieceDeletions()`
    - `getActiveRootCount()` → `getActivePieceCount()`
  - Event renames:
    - `ProofSetCreated` → `DataSetCreated` (parameter change: `owner` → `storageProvider`)
    - `ProofSetDeleted` → `DataSetDeleted`
    - `ProofSetEmpty` → `DataSetEmpty`
    - `ProofSetOwnerChanged` → `StorageProviderChanged` (parameters: `oldOwner`/`newOwner` → `oldStorageProvider`/`newStorageProvider`)
    - `RootsAdded` → `PiecesAdded` (parameter change: `rootIds` → `pieceIds`)
    - `RootsRemoved` → `PiecesRemoved` (parameter change: `rootIds` → `pieceIds`)
    - `PossessionProven` event updated: `IPDPTypes.RootIdAndOffset[]` → `IPDPTypes.PieceIdAndOffset[]`
  - Interface updates:
    - `PDPListener` interface method renames:
      - `proofSetCreated()` → `dataSetCreated()` (parameter change: `proofSetId` → `dataSetId`)
      - `proofSetDeleted()` → `dataSetDeleted()` (parameter change: `proofSetId` → `dataSetId`)
      - `rootsAdded()` → `piecesAdded()` (parameter changes: `proofSetId` → `dataSetId`, `IPDPTypes.RootData[]` → `IPDPTypes.PieceData[]`)
      - `rootsScheduledRemove()` → `piecesScheduledRemove()` (parameter changes: `proofSetId` → `dataSetId`, `rootIds` → `pieceIds`)
      - `possessionProven()` → unchanged name (parameter change: `proofSetId` → `dataSetId`)
      - `nextProvingPeriod()` → unchanged name (parameter change: `proofSetId` → `dataSetId`)
      - `ownerChanged()` → `storageProviderChanged()` (parameters: `proofSetId` → `dataSetId`, `oldOwner`/`newOwner` → `oldStorageProvider`/`newStorageProvider`)
    - `IPDPTypes.RootData` → `IPDPTypes.PieceData` (note: struct field remains `piece`)
  - Storage renames:
    - Constants:
      - `MAX_ROOT_SIZE` → `MAX_PIECE_SIZE`
      - `VERSION = "1.1.0"` → `VERSION = "2.0.0"` (to reflect this release)
    - State variables:
      - `nextProofSetId` → `nextDataSetId` (uint64)
    - Mappings:
      - `nextRootId` → `nextPieceId`
      - `proofSetLeafCount` → `dataSetLeafCount`
      - `proofSetListener` → `dataSetListener`
      - `proofSetLastProvenEpoch` → `dataSetLastProvenEpoch`
      - `proofSetOwner` → `storageProvider`
      - `proofSetProposedOwner` → `dataSetProposedStorageProvider`
      - `rootCids` → `pieceCids`
      - `rootLeafCounts` → `pieceLeafCounts`

### Deprecated
- **SimplePDPService**: No longer actively maintained or deployed by default
  - Removed from default deployment scripts (`deploy-mainnet.sh`, `deploy-calibnet.sh`, `deploy-devnet.sh`)
  - Added optional deployment script (`deploy-simple-pdp-service.sh`) for community use
  - Remains available as reference integration in `src/SimplePDPService.sol`. Proper Filecoin Service with PDP can be found in https://github.com/FilOzone/filecoin-services/tree/main/service_contracts/src

## [1.1.0] - 2025-01-20
### Added
- Contract migration functionality
- Enhanced upgrade mechanisms

## [1.0.0] - 2025-04-17
### Added
- Initial release of PDPVerifier and SimplePDPService contracts
- Data set management functionality, ownership and programmability
- Grinding secure piece addition and removal capabilities
- Useful events emitted from PDPVerifier during data set operations
- Extensible PDPListener architecture
- Possession proving mechanism 
- Challenge generation through integration filecoin randomness precompile 
- Integration with Pyth Network for FIL/USD price feeds
- Fee calculation and burning mechanisms
- Upgradeable contract architecture
- SimplePDPService Faulting events 
- SimplePDPService challenge window and proving period


## Template for future releases:

## [X.Y.Z] - YYYY-MM-DD
### Added
- New features or capabilities

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features or capabilities

### Fixed
- Bug fixes

### Security
- Security-related changes or improvements

### Performance
- Performance-related improvements

[Unreleased]: https://github.com/filozone/pdp/compare/v3.4.0...HEAD
[3.4.0]: https://github.com/filozone/pdp/compare/v3.3.0...v3.4.0
[3.3.0]: https://github.com/filozone/pdp/compare/v3.2.0...v3.3.0
[3.2.0]: https://github.com/filozone/pdp/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/filozone/pdp/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/filozone/pdp/compare/v2.2.1...v3.0.0
[2.2.1]: https://github.com/filozone/pdp/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/filozone/pdp/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/filozone/pdp/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/filozone/pdp/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/filozone/pdp/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/filozone/pdp/releases/tag/v1.0.0
