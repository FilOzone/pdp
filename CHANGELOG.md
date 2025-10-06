# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

## [2.2.0] - 2025-10-06

### Deployed

**Mainnet:**
- PDPVerifier Implementation: [Address_To_Be_Published]
- PDPVerifier Proxy: [Address_To_Be_Published]

**Calibnet:**
- PDPVerifier Implementation: [Address_To_Be_Published]
- PDPVerifier Proxy: [Address_To_Be_Published]

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

[Unreleased]: https://github.com/filozone/pdp/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/filozone/pdp/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/filozone/pdp/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/filozone/pdp/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/filozone/pdp/releases/tag/v1.0.0
