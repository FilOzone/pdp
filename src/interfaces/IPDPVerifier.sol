// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Cids} from "../Cids.sol";
import {IPDPTypes} from "./IPDPTypes.sol";
import {IPDPEvents} from "./IPDPEvents.sol";

/// @title IPDPVerifier
/// @notice Main interface for the PDPVerifier contract
interface IPDPVerifier is IPDPEvents {
    // View functions
    function getChallengeFinality() external view returns (uint256);
    function getNextDataSetId() external view returns (uint64);
    function dataSetLive(uint256 setId) external view returns (bool);
    function pieceLive(uint256 setId, uint256 pieceId) external view returns (bool);
    function pieceChallengable(uint256 setId, uint256 pieceId) external view returns (bool);
    function getDataSetLeafCount(uint256 setId) external view returns (uint256);
    function getNextPieceId(uint256 setId) external view returns (uint256);
    function getNextChallengeEpoch(uint256 setId) external view returns (uint256);
    function getDataSetListener(uint256 setId) external view returns (address);
    function getDataSetStorageProvider(uint256 setId) external view returns (address, address);
    function getDataSetLastProvenEpoch(uint256 setId) external view returns (uint256);
    function getPieceCid(uint256 setId, uint256 pieceId) external view returns (bytes memory);
    function getPieceLeafCount(uint256 setId, uint256 pieceId) external view returns (uint256);
    function getChallengeRange(uint256 setId) external view returns (uint256);
    function getScheduledRemovals(uint256 setId) external view returns (uint256[] memory);

    // State-changing functions
    function proposeDataSetStorageProvider(uint256 setId, address newStorageProvider) external;
    function claimDataSetStorageProvider(uint256 setId, bytes calldata extraData) external;
    function createDataSet(address listenerAddr, bytes calldata extraData) external payable returns (uint256);
    function deleteDataSet(uint256 setId, bytes calldata extraData) external;
    function addPieces(uint256 setId, Cids.Cid[] calldata pieceData, bytes calldata extraData)
        external
        returns (uint256);
    function schedulePieceDeletions(uint256 setId, uint256[] calldata pieceIds, bytes calldata extraData) external;
    function provePossession(uint256 setId, IPDPTypes.Proof[] calldata proofs) external payable;
    function nextProvingPeriod(uint256 setId, uint256 challengeEpoch, bytes calldata extraData) external;
    function findPieceIds(uint256 setId, uint256[] calldata leafIndexs)
        external
        view
        returns (IPDPTypes.PieceIdAndOffset[] memory);
}
