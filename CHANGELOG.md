# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

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

[Unreleased]: https://github.com/filozone/pdp/compare/v3.1.0...HEAD
[3.1.0]: https://github.com/filozone/pdp/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/filozone/pdp/compare/v2.2.1...v3.0.0
[2.2.1]: https://github.com/filozone/pdp/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/filozone/pdp/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/filozone/pdp/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/filozone/pdp/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/filozone/pdp/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/filozone/pdp/releases/tag/v1.0.0
