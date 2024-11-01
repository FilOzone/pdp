// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SimplePDPService} from "./SimplePDPService.sol";
import {PDPVerifier} from "./PDPVerifier.sol";
import {Cids} from "./Cids.sol";



// Run lottery upon submitting proof to be compensated for storing the data
contract LotteryDAOService {
    
    // State variables
    uint256 public totalProviders;
    mapping(address => uint256) public spID;
    mapping(address => bool) public registeredProviders;
    mapping(uint256 => address) public proofSetToSP;
    mapping(bytes => bool) public allowedCids;

    event Debug(string message, bytes data);

    constructor(
        Cids.Cid[] memory _allowedCids
    ) {
        // Initialize allowed Cids
        for (uint i = 0; i < _allowedCids.length; i++) {
            emit Debug("allowedCid", _allowedCids[i].data);
            Cids.Cid memory cid = _allowedCids[i];
            allowedCids[cid.data] = true;
        }
    }

    // Fund management functions
    receive() external payable {}

    // PDPService interface implementation
    function getMaxProvingPeriod() public pure  returns (uint64) {
        return 2880;
    }

    function getChallengesPerProof() public pure  returns (uint64) {
        return 5;
    }

    function proofSetCreated(uint256 proofSetId, address creator) external  {
        if (registeredProviders[creator]) {
            revert("Provider already registered");
        }
        registeredProviders[creator] = true;
        spID[creator] = totalProviders;
        totalProviders++;
        proofSetToSP[proofSetId] = creator;
    }

    function proofSetRemoved(uint256 proofSetId) external {
        return;
    }

    function rootsAdded(
        uint256 proofSetId, 
        uint256 firstAdded, 
        PDPVerifier.RootData[] calldata rootData
    ) external  {
        // Verify all roots are allowed
        for (uint i = 0; i < rootData.length; i++) {
            emit Debug("rootData", rootData[i].root.data);
            require(allowedCids[rootData[i].root.data], "Root CID not allowed");
        }
    }

    function rootsScheduledRemove(uint256 proofSetId, uint256[] memory rootIds) external  {
        return;
    }

    address constant RANDOMNESS_PRECOMPILE = 0xfE00000000000000000000000000000000000006;
    function getRandomness(uint64 epoch) public view returns (bytes32) {
        // Prepare the input data (epoch as a uint256)
        uint256 input = uint256(epoch);

        // Call the precompile
        (bool success, bytes memory result) = RANDOMNESS_PRECOMPILE.staticcall(abi.encodePacked(input));

        // Check if the call was successful
        require(success, "Randomness precompile call failed");

        // Decode and return the result
        return abi.decode(result, (bytes32));
    }

    function posessionProven(
        uint256 proofSetId, 
        uint256 challengedLeafCount, 
        uint256 seed, 
        uint256 challengeCount
    ) external  {
        // Get provider address and verify they are registered
        address provider = proofSetToSP[proofSetId];
        require(registeredProviders[provider], "Provider not registered");

        // Get current block's randomness
        bytes32 randomness = getRandomness(uint64(block.number));
        
        // Convert randomness to uint and get modulo of total providers
        uint256 randomNumber = uint256(randomness);
        uint256 winningId = randomNumber % (totalProviders - 1);

        // Check if this provider's ID matches the winning number
        if (spID[provider] == winningId) {
            // Calculate prize as 1/1000000 of contract balance
            uint256 prize = address(this).balance / 1000000;
            
            // Transfer prize to winning provider
            if (prize > 0) {
                (bool success, ) = provider.call{value: prize}("");
                require(success, "Prize transfer failed");
            }
        }
    }

    function nextProvingPeriod(uint256 proofSetId, uint256 leafCount) external {
        return;
    }
}