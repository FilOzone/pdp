# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

## [2.1.0] - 2025-07-21
### Changed
- **BREAKING**: Completed terminology updates from PR #180 feedback
  - Function renames:
    - `scheduleRemovals()` → `schedulePieceDeletions()` - Better describes the action of deleting pieces
    - `MAX_ROOT_SIZE` → `MAX_PIECE_SIZE` - Consistent with piece terminology
  - Event parameter renames:
    - `StorageProviderChanged` event: `oldOwner`/`newOwner` → `oldStorageProvider`/`newStorageProvider`
  - Test updates:
    - All test classes, functions, and variables updated from "owner/ownership" to "storage provider" terminology
    - Consistent use of full "StorageProvider" naming (not abbreviated as "Provider")
  - Documentation and comment updates:
    - All instances of "proof set" → "data set" (two words in documentation)
    - All instances of "dataset" → "data set" (two words in documentation)
    - Remaining "root" references in gas benchmarks updated to "piece"
  - Script updates:
    - `claimDataSetOwnership()` → `claimDataSetStorageProvider()` in claim-owner.sh
    - `proposeDataSetOwner()` → `proposeDataSetStorageProvider()` in propose-owner.sh

### Fixed
- Gas benchmark documentation and CSV files now use consistent "DataSet" and "Piece" terminology
- All comments and documentation now consistently use "data set" as two words

## [2.0.0] - 2025-07-20
### Changed
- **BREAKING**: Renamed core terminology throughout the codebase for better clarity
  - `proofSet` → `dataSet` (all functions, variables, events, and parameters)
  - `root` → `piece` (all functions, variables, events, and parameters)
  - `rootId` → `pieceId` (all functions, variables, events, and parameters)
  - Function renames:
    - `createProofSet()` → `createDataSet()`
    - `deleteProofSet()` → `deleteDataSet()`
    - `getProofSet*()` → `getDataSet*()`
    - `getNextProofSetId()` → `getNextDataSetId()`
    - `proofSetLive()` → `dataSetLive()`
    - `getProofSetLeafCount()` → `getDataSetLeafCount()`
    - `getNextRootId()` → `getNextPieceId()`
    - `rootLive()` → `pieceLive()`
    - `rootChallengable()` → `pieceChallengable()`
    - `getRootMetadata()` → `getPieceMetadata()`
    - And many more...
  - Event renames:
    - `ProofSetCreated` → `DataSetCreated`
    - `ProofSetDeleted` → `DataSetDeleted`
    - `ProofSetEmpty` → `DataSetEmpty`
    - `ProofSetOwnerChanged` → `StorageProviderChanged`
    - `RootsAdded` → `PiecesAdded`
    - `RootsRemoved` → `PiecesRemoved`
    - `RootMetadataAdded` → `PieceMetadataAdded`
  - Interface updates:
    - `PDPListener` interface methods updated with new parameter names
    - `IPDPTypes.RootData` → `IPDPTypes.PieceData` (note: struct field remains `piece`)
  - Variable and mapping renames:
    - `nextProofSetId` → `nextDataSetId`
    - `proofSetLeafCount` → `dataSetLeafCount`
    - `proofSetListener` → `dataSetListener`
    - `proofSetOwner` → `storageProvider`
    - `rootCids` → `pieceCids`
    - `rootLeafCounts` → `pieceLeafCounts`
    - `nextRootId` → `nextPieceId`

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

[Unreleased]: https://github.com/filozone/pdp/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/filozone/pdp/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/filozone/pdp/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/filozone/pdp/releases/tag/v1.0.0
