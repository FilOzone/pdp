// SPDX-License-Identifier: MIT
// The verification functions are adapted from OpenZeppelin Contracts (last updated v5.0.0) (utils/cryptography/MerkleProof.sol)

pragma solidity ^0.8.20;

import {BitOps} from "./BitOps.sol";

/**
 * Functions for the generation and verification of Merkle proofs.
 * These are specialised to the hash function of SHA254 and implicitly balanced trees.
 * 
 * Note that only the verification functions are intended to execute on-chain.
 * The commitment and proof generation functions are co-located for convenience and to function
 * as a specification for off-chain operations.
 */
library MerkleVerify {
    /**
     * Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root` at `position`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree.
     *
     * Will only return true if the leaf is at the bottom of the tree for the given tree height
     *
     * This version handles proofs in memory.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf, uint256 position, uint256 treeHeight) internal view returns (bool) {
        // Tree heigh includes root, proof does not 
        require(proof.length == treeHeight - 1, "proof length does not match tree height");
        return processInclusionProofMemory(proof, leaf, position) == root;
    }

    /**
     * Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` at `position` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree.  
     *
     * This version handles proofs in memory.
     */
    function processInclusionProofMemory(bytes32[] memory proof, bytes32 leaf, uint256 position) internal view returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            // If position is even, the leaf/node is on the left and sibling is on the right.
            bytes32 sibling = proof[i];
            if (position % 2 == 0) {
                computedHash = Hashes.orderedHash(computedHash, sibling);
            } else {
                computedHash = Hashes.orderedHash(sibling, computedHash);
            }
            position /= 2;
        }
        return computedHash;
    }

    /**
     * Returns the root of a Merkle tree of all zero leaves and specified height. 
     * A height of zero returns zero (the leaf value).
     * A height of 1 returns the hash of two zero leaves.
     * A height of n returns the hash of two nodes of height n-1.
     * Height must be <= 50 (representing 2^50 leaves or 32EiB).
     */
    function zeroRoot(uint height) internal pure returns (bytes32) {
        require(height <= 50, "Height must be <= 50");        
        // These roots were generated by code in Proots.t.sol.
        uint256[51] memory ZERO_ROOTS = [
            0x0000000000000000000000000000000000000000000000000000000000000000,
            0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb0b,
            0x3731bb99ac689f66eef5973e4a94da188f4ddcae580724fc6f3fd60dfd488333,
            0x642a607ef886b004bf2c1978463ae1d4693ac0f410eb2d1b7a47fe205e5e750f,
            0x57a2381a28652bf47f6bef7aca679be4aede5871ab5cf3eb2c08114488cb8526,
            0x1f7ac9595510e09ea41c460b176430bb322cd6fb412ec57cb17d989a4310372f,
            0xfc7e928296e516faade986b28f92d44a4f24b935485223376a799027bc18f833,
            0x08c47b38ee13bc43f41b915c0eed9911a26086b3ed62401bf9d58b8d19dff624,
            0xb2e47bfb11facd941f62af5c750f3ea5cc4df517d5c4f16db2b4d77baec1a32f,
            0xf9226160c8f927bfdcc418cdf203493146008eaefb7d02194d5e548189005108,
            0x2c1a964bb90b59ebfe0f6da29ad65ae3e417724a8f7c11745a40cac1e5e74011,
            0xfee378cef16404b199ede0b13e11b624ff9d784fbbed878d83297e795e024f02,
            0x8e9e2403fa884cf6237f60df25f83ee40dca9ed879eb6f6352d15084f5ad0d3f,
            0x752d9693fa167524395476e317a98580f00947afb7a30540d625a9291cc12a07,
            0x7022f60f7ef6adfa17117a52619e30cea82c68075adf1c667786ec506eef2d19,
            0xd99887b973573a96e11393645236c17b1f4c7034d723c7a99f709bb4da61162b,
            0xd0b530dbb0b4f25c5d2f2a28dfee808b53412a02931f18c499f5a254086b1326,
            0x84c0421ba0685a01bf795a2344064fe424bd52a9d24377b394ff4c4b4568e811,
            0x65f29e5d98d246c38b388cfc06db1f6b021303c5a289000bdce832a9c3ec421c,
            0xa2247508285850965b7e334b3127b0c042b1d046dc54402137627cd8799ce13a,
            0xdafdab6da9364453c26d33726b9fefe343be8f81649ec009aad3faff50617508,
            0xd941d5e0d6314a995c33ffbd4fbe69118d73d4e5fd2cd31f0f7c86ebdd14e706,
            0x514c435c3d04d349a5365fbd59ffc713629111785991c1a3c53af22079741a2f,
            0xad06853969d37d34ff08e09f56930a4ad19a89def60cbfee7e1d3381c1e71c37,
            0x39560e7b13a93b07a243fd2720ffa7cb3e1d2e505ab3629e79f46313512cda06,
            0xccc3c012f5b05e811a2bbfdd0f6833b84275b47bf229c0052a82484f3c1a5b3d,
            0x7df29b69773199e8f2b40b77919d048509eed768e2c7297b1f1437034fc3c62c,
            0x66ce05a3667552cf45c02bcc4e8392919bdeac35de2ff56271848e9f7b675107,
            0xd8610218425ab5e95b1ca6239d29a2e420d706a96f373e2f9c9a91d759d19b01,
            0x6d364b1ef846441a5a4a68862314acc0a46f016717e53443e839eedf83c2853c,
            0x077e5fde35c50a9303a55009e3498a4ebedff39c42b710b730d8ec7ac7afa63e,
            0xe64005a6bfe3777953b8ad6ef93f0fca1049b2041654f2a411f7702799cece02,
            0x259d3d6b1f4d876d1185e1123af6f5501af0f67cf15b5216255b7b178d12051d,
            0x3f9a4d411da4ef1b36f35ff0a195ae392ab23fee7967b7c41b03d1613fc29239,
            0xfe4ef328c61aa39cfdb2484eaa32a151b1fe3dfd1f96dd8c9711fd86d6c58113,
            0xf55d68900e2d8381eccb8164cb9976f24b2de0dd61a31b97ce6eb23850d5e819,
            0xaaaa8c4cb40aacee1e02dc65424b2a6c8e99f803b72f7929c4101d7fae6bff32,
            0xc91a84c057fd4afcc209c3b482360cf7493b9129fa164cd1fe6b045a683b5322,
            0x64a2c1df312ecb443b431946c02fe701514b5291091b888f03189bee8ea11416,
            0x739953434ead6e24f1d1bf5b68ca823b2692b3000a7806d08c76640da98c3526,
            0x771f5b63af6f7d1d515d134084d535f5f4d8ab8529b2c3f581f143f8cc38be2f,
            0x9031a15bf51550a85db1f64f4db739e01125478a50ee332bc2b4f6462214b20b,
            0xc83ba84710b74413f3be84a5466aff2d7f0c5472248ffbeb2266466a92ac4f12,
            0x2fe598945de393714c10f447cec237039b5944077a78e0a9811cf5f7a45abe1b,
            0x395355ae44754a5cde74898a3f2ef60d5871ab35019c610fc413a62d57646501,
            0x4bd4712084416c77eec00cab23416eda8c8dbf681c8ccd0b96c0be980a40d818,
            0xf6eeae7dee22146564155ebe4bdf633333401de68da4aa2a6e946c2363807a34,
            0x8b43a114ba1c1bb80781e85f87b0bbee11c69fdbbd2ed81d6c9b4c7859c04e34,
            0xf74dc344ee4fa47f07fb2732ad9443d94892ca8b53d006c9891a32ef2b74491e,
            0x6f5246ae0f965e5424162403d3ab81ef8d15439c5f3a49038488e3640ef98718,
            0x0b5b44ccf91ff135af58d2cf694b2ac99f22f5264863d6b9272b6155956aa10e
        ];
        return bytes32(ZERO_ROOTS[height]);
    }
}

library MerkleProve {
    // Builds a merkle tree from an array of leaves.
    // The tree is an array of arrays of bytes32.
    // The last array is the leaves, and each prior array is the result of the hash of pairs in the previous array.
    // An unpaired element is paired with the root of a tree of the same height with zero leaves.
    // The first element of the first array is the root.
    function buildTree(bytes32[] memory leaves) internal view returns (bytes32[][] memory) {
        require(leaves.length > 0, "Leaves array must not be empty");

        uint256 levels = 256 - BitOps.clz(leaves.length - 1);
        bytes32[][] memory tree = new bytes32[][](levels + 1);
        tree[levels] = leaves;

        for (uint256 i = levels; i > 0; i--) {
            bytes32[] memory currentLevel = tree[i];
            uint256 nextLevelSize = (currentLevel.length + 1) / 2;
            tree[i - 1] = new bytes32[](nextLevelSize);

            for (uint256 j = 0; j < nextLevelSize; j++) {
                if (2 * j + 1 < currentLevel.length) {
                    tree[i - 1][j] = Hashes.orderedHash(currentLevel[2 * j], currentLevel[2 * j + 1]);
                } else {
                    // Pair final odd node with a zero-tree of same height.
                    tree[i - 1][j] = Hashes.orderedHash(currentLevel[2 * j], MerkleVerify.zeroRoot(levels - i));
                }
            }
        }

        return tree;
    }

    // Gets an inclusion proof from a Merkle tree for a leaf at a given index.
    // The proof is constructed by traversing up the tree to the root, and the sibling of each node is appended to the proof.
    // A final unpaired element in any level is paired with the zero-tree of the same height.
    // Every proof thus has length equal to the height of the tree minus 1.
    function buildProof(bytes32[][] memory tree, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < tree[tree.length - 1].length, "Index out of bounds");

        bytes32[] memory proof = new bytes32[](tree.length - 1);
        uint256 proofIndex = 0;

        for (uint256 i = tree.length - 1; i > 0; i--) {
            uint256 levelSize = tree[i].length;
            uint256 pairIndex = index ^ 1; // XOR with 1 to get the pair index

            if (pairIndex < levelSize) {
                proof[proofIndex] = tree[i][pairIndex];
            } else {
                // Pair final odd node with zero-tree of same height.
                proof[proofIndex] = MerkleVerify.zeroRoot(tree.length - 1 - i);
            }
            proofIndex++;
            index /= 2; // Move to the parent node
        }
        return proof;
    }
}

library Hashes {
    // "The Sha254 functions are identical to Sha256 except that the last two bits of the Sha256 256-bit digest are zeroed out."
    // The bytes of uint256 are arranged in big-endian order, MSB first in memory.
    // The bits in each byte are arranged in little-endian order.
    // Thus, the "last two bits" are the first two bits of the last byte.
    uint256 constant SHA254_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF3F;

    /** Order-dependent hash of pair of bytes32. */
    function orderedHash(bytes32 a, bytes32 b) internal view returns (bytes32) {
        return _efficientSHA254(a, b);
    }

    /** Implementation equivalent to using sha256(abi.encode(a, b)) that doesn't allocate or expand memory. */
    function _efficientSHA254(bytes32 a, bytes32 b) private view returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            
            // Call the SHA256 precompile
            if iszero(staticcall(gas(), 0x2, 0x00, 0x40, 0x00, 0x20)) {
                revert(0, 0)
            }
            
            value := mload(0x00)
            // SHA254 hash for compatibility with Filecoin piece commitments.
            value := and(value, SHA254_MASK)
        }
    }
}
