// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.20;

uint256 constant PADDING_MAX = (uint256(1) << 55) - 1;
uint256 constant HEIGHT_MAX = (uint256(1) << 6) - 1;
uint256 constant LEAF_COUNT_MAX = (uint256(1) << 51) - 1;
uint256 constant SUM_TREE_MAX = (uint256(1) << 144) - 1;

uint256 constant HEIGHT_SHIFT = 55;
uint256 constant LEAF_COUNT_SHIFT = 61;
uint256 constant SUM_TREE_SHIFT = 112;

error PieceMetadataOverflow();

type PieceMetadata is uint256;

using PieceMetadataLibrary for PieceMetadata global;

library PieceMetadataLibrary {
    function pack(uint256 piecePadding, uint256 pieceHeight, uint256 pieceLeafCount, uint256 treeSum)
        internal
        pure
        returns (PieceMetadata)
    {
        if (
            piecePadding > PADDING_MAX || pieceHeight > HEIGHT_MAX || pieceLeafCount > LEAF_COUNT_MAX
                || treeSum > SUM_TREE_MAX
        ) {
            revert PieceMetadataOverflow();
        }
        return PieceMetadata.wrap(
            piecePadding | (pieceHeight << HEIGHT_SHIFT) | (pieceLeafCount << LEAF_COUNT_SHIFT)
                | (treeSum << SUM_TREE_SHIFT)
        );
    }

    function padding(PieceMetadata metadata) internal pure returns (uint256) {
        return PieceMetadata.unwrap(metadata) & PADDING_MAX;
    }

    function height(PieceMetadata metadata) internal pure returns (uint256) {
        return (PieceMetadata.unwrap(metadata) >> HEIGHT_SHIFT) & HEIGHT_MAX;
    }

    function leafCount(PieceMetadata metadata) internal pure returns (uint256) {
        return (PieceMetadata.unwrap(metadata) >> LEAF_COUNT_SHIFT) & LEAF_COUNT_MAX;
    }

    function sum(PieceMetadata metadata) internal pure returns (uint256) {
        return (PieceMetadata.unwrap(metadata) >> SUM_TREE_SHIFT) & SUM_TREE_MAX;
    }

    function withSum(PieceMetadata metadata, uint256 newSum) internal pure returns (PieceMetadata) {
        if (newSum > SUM_TREE_MAX) revert PieceMetadataOverflow();
        uint256 rawMetadata = PieceMetadata.unwrap(metadata);
        return PieceMetadata.wrap((rawMetadata & ~(SUM_TREE_MAX << SUM_TREE_SHIFT)) | (newSum << SUM_TREE_SHIFT));
    }

    function clearExceptSum(PieceMetadata metadata) internal pure returns (PieceMetadata) {
        return PieceMetadata.wrap(PieceMetadata.unwrap(metadata) & (SUM_TREE_MAX << SUM_TREE_SHIFT));
    }
}
