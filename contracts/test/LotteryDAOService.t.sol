// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LotteryDAOService} from "../src/LotteryDAOService.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {Cids} from "../src/Cids.sol";

contract LotteryDAOServiceTest is Test {
    LotteryDAOService public lotteryDAO;
    address public alice = address(0x1);
    address public bob = address(0x2);
    
    function setUp() public {
        // Create sample allowed CIDs
        Cids.Cid[] memory allowedCids = new Cids.Cid[](2);
        bytes memory prefix = "prefix";
        bytes32 digest1 = bytes32(uint256(1));
        bytes32 digest2 = bytes32(uint256(2));
        allowedCids[0] = Cids.cidFromDigest(prefix, digest1);
        allowedCids[1] = Cids.cidFromDigest(prefix, digest2);
        
        lotteryDAO = new LotteryDAOService(allowedCids);
        
        // Fund the contract
        vm.deal(address(lotteryDAO), 100 ether);
    }

    function testInitialState() public {
        assertEq(lotteryDAO.totalProviders(), 0);
        assertEq(lotteryDAO.getMaxProvingPeriod(), 2880);
        assertEq(lotteryDAO.getChallengesPerProof(), 5);
    }

    function testProviderRegistration() public {
        uint256 proofSetId = 1;
        
        lotteryDAO.proofSetCreated(proofSetId, alice);
        
        assertTrue(lotteryDAO.registeredProviders(alice));
        assertEq(lotteryDAO.spID(alice), 0);
        assertEq(lotteryDAO.totalProviders(), 1);
        assertEq(lotteryDAO.proofSetToSP(proofSetId), alice);
    }

    function testCannotRegisterTwice() public {
        lotteryDAO.proofSetCreated(1, alice);
        
        vm.expectRevert("Provider already registered");
        lotteryDAO.proofSetCreated(2, alice);
    }

    function testRootsAddedValidation() public {
        PDPVerifier.RootData[] memory rootData = new PDPVerifier.RootData[](1);
        bytes memory prefix = "prefix";
        bytes32 digest1 = bytes32(uint256(1));
        Cids.Cid memory okCid = Cids.cidFromDigest(prefix, digest1);
        rootData[0] = PDPVerifier.RootData({
            root: okCid, // Using allowed CID
            rawSize: 100
        });

        lotteryDAO.rootsAdded(1, 0, rootData);

        // Test with invalid CID
        PDPVerifier.RootData[] memory invalidRootData = new PDPVerifier.RootData[](1);
        bytes32 digest2 = bytes32(uint256(3));
        Cids.Cid memory badCid = Cids.cidFromDigest(prefix, digest2);
        invalidRootData[0] = PDPVerifier.RootData({
            root: badCid, // Using non-allowed CID
            rawSize: 100
        });

        vm.expectRevert("Root CID not allowed");
        lotteryDAO.rootsAdded(1, 0, invalidRootData);
    }

    function testPossessionProvenLottery() public {
        // Register two providers
        lotteryDAO.proofSetCreated(1, alice);
        lotteryDAO.proofSetCreated(2, bob);
        
        uint256 initialBalance = address(alice).balance;
        
        // Mock randomness to make alice win
        uint256 mockRandomness = 0; // This will make ID 0 (alice) win
        vm.mockCall(
            0xfE00000000000000000000000000000000000006,
            abi.encodePacked(uint256(block.number)),
            abi.encode(bytes32(mockRandomness))
        );
        
        // Prove possession for alice
        lotteryDAO.posessionProven(1, 100, 123, 5);
        
        // Check if alice received prize (1/1000000 of contract balance)
        uint256 expectedPrize = 100 ether / 1000000;
        assertEq(address(alice).balance - initialBalance, expectedPrize);
    }

    receive() external payable {}
}