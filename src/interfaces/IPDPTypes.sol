// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Cids} from "../Cids.sol";

/// @title IPDPTypes
/// @notice Shared types for PDP contracts and consumers
interface IPDPTypes {
    struct PieceData {
        Cids.Cid piece;
        uint256 rawSize;
    }

    struct Proof {
        bytes32 leaf;
        bytes32[] proof;
    }

    struct PieceIdAndOffset {
        uint256 pieceId;
        uint256 offset;
    }
} 