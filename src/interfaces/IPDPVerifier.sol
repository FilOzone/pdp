// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPDPTypes.sol";
import "./IPDPEvents.sol";

/// @title IPDPVerifier
/// @notice Main interface for the PDPVerifier contract
interface IPDPVerifier is IPDPEvents {
    // View functions
    function getChallengeFinality() external view returns (uint256);
    function getNextProofSetId() external view returns (uint64);
    function proofSetLive(uint256 setId) external view returns (bool);
    function rootLive(uint256 setId, uint256 rootId) external view returns (bool);
    function rootChallengable(uint256 setId, uint256 rootId) external view returns (bool);
    function getProofSetLeafCount(uint256 setId) external view returns (uint256);
    function getNextRootId(uint256 setId) external view returns (uint256);
    function getNextChallengeEpoch(uint256 setId) external view returns (uint256);
    function getProofSetListener(uint256 setId) external view returns (address);
    function getProofSetOwner(uint256 setId) external view returns (address, address);
    function getProofSetLastProvenEpoch(uint256 setId) external view returns (uint256);
    function getRootCid(uint256 setId, uint256 rootId) external view returns (bytes memory);
    function getRootLeafCount(uint256 setId, uint256 rootId) external view returns (uint256);
    function getChallengeRange(uint256 setId) external view returns (uint256);
    function getScheduledRemovals(uint256 setId) external view returns (uint256[] memory);

    // State-changing functions
    function proposeProofSetOwner(uint256 setId, address newOwner) external;
    function claimProofSetOwnership(uint256 setId) external;
    function createProofSet(address listenerAddr, bytes calldata extraData) external payable returns (uint256);
    function deleteProofSet(uint256 setId, bytes calldata extraData) external;
    function addRoots(uint256 setId, IPDPTypes.RootData[] calldata rootData, bytes calldata extraData) external returns (uint256);
    function scheduleRemovals(uint256 setId, uint256[] calldata rootIds, bytes calldata extraData) external;
    function provePossession(uint256 setId, IPDPTypes.Proof[] calldata proofs) external payable;
    function nextProvingPeriod(uint256 setId, uint256 challengeEpoch, bytes calldata extraData) external;
    function findRootIds(uint256 setId, uint256[] calldata leafIndexs) external view returns (IPDPTypes.RootIdAndOffset[] memory);
} 