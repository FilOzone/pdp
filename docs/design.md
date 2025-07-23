# Provable Data Possession - Design Documentation

## Overview
Provable Data Possession (PDP) is a protocol that allows storage providers to prove they possess specific data without revealing the data itself. The system operates through a set of smart contracts that manage data sets, verification, and fault reporting.

PDP currently enables a client-storage provider relationship where:
1. Clients and storage providers establish a data set for data storage verification
2. Storage providers add data pieces to the data set and submit periodic proofs
3. The system verifies these proofs using randomized challenges
4. Faults are reported when proofs fail or are not submitted


## Table of Contents
1. [Architecture](#architecture)
2. [Core Components](#core-components)
3. [Data Structures](#data-structures)
4. [Workflows](#workflows)
5. [Security Considerations](#security-considerations)
6. [Performance Considerations](#performance-considerations)
7. [Future Enhancements](#future-enhancements)
8. [Appendices](#appendices)

## Architecture
The PDP system uses a singleton contract design where a single verifier contract manages multiple data sets for many storage providers.

### System Components
- **PDP Verifier**: The main contract that holds data sets and verifies proofs
- **SimplePDPService**: Manages proving periods and fault reporting
- **Supporting Contracts**: Additional contracts for specific functionality

### Interaction Patterns
The PDP system follows these primary interaction patterns:
1. Clients and storage providers establish data sets through the verifier contract
2. The system issues challenges based on chain randomness
3. Storage providers submit merkleproofs for data possession verification
4. The SimplePDPService contract (or in general the listener) receives events about all operations
5. Faults are reported when proofs are not submitted

## Core Components

### PDP Verifier
- **Purpose**: Manages data sets and verifies proofs
- **Key methods**:
  - Create data sets
  - Add/delete pieces to data sets
  - Verify proofs
  - Manage proving periods
- **State management**: Maintains data set state including pieces, sizes, and challenge epochs

Search over data set data to find a challenged leaf is the heart of the PDPVerifier.  To do this efficiently the verifier needs binary search.  To implement binary search efficiently with a mutating array of data set pieces we use a Fenwick/BIT tree variant.  See the design document: https://www.notion.so/filecoindev/PDP-Logical-Array-4405cda734964622993d3d58389942e8

Much of the design of the verifier comes down to preventing proving parties from grinding attacks: See grinding prevention design document: https://www.notion.so/filecoindev/PDP-Grinding-Mitigations-1a3dc41950c180de9403cc2bb5c14bbb

The verifier charges for its services with a proof fee. See the working proof fee design document: https://www.notion.so/filecoindev/Pricing-mechanism-for-PDPverifier-12adc41950c180ea9608cb419c369ba4

For historical context please see the original design document of what has become the verifier: https://docs.google.com/document/d/1VwU182XZb54d__FQqMIJ_Srpk5a65QlDv_ffktnhDN0/edit?tab=t.0#heading=h.jue9m7srjcr3



### PDP Listener
The listener contract is a design pattern allowing for extensibile programmability of the PDP storage protocol.  Itcoordinates a concrete storage agreement between a storage client and provider using the PDPVerifier's proving service.

See the design document: https://www.notion.so/filecoindev/PDP-Extensibility-The-Listener-Contract-1a3dc41950c1804b9a21c15bc0abc95f

Included is a default instantiation -- the SimplePDPService.

### SimplePDPService

This is the default instantiation of the PDPListener.

- **Fault handling**: Reports faults when proving fails
- **Proving period management**: Manages the timing of proof challenges
- **Challenge window implementation**: Enforces time constraints for proof submission

## Data Structures
Detailed description of key data structures.

### DataSet
A data set is a logical container that holds an ordered collection of Merkle roots representing arrays of data:

```solidity
struct Piece {
    id: u64
    data: CID,
    size: u64, // Must be multiple of 32.
}
struct DataSet {
    id: u64,
    // Protocol enforced delay in epochs between a successful proof and availability of
    // the next challenge.
    challengeDelay: u64,
    // ID to assign to the next piece (a sequence number).
    nextPieceID: u64,
    // Pieces in the data set.
    pieces: Piece[],
    // The total size of all pieces.
    totalSize: u64,
    // Epoch from which to draw the next challenge.
    nextChallengeEpoch: u64,
}
```

### Proof Structure
Each proof certifies the inclusion of a leaf at a specified position within a Merkle tree:

```solidity
struct Proof {
    leaf: bytes32,
    leafOffset: uint,
    proof: bytes32[],
}
```

### Logical Array Implementation
The PDP Logical Array is implemented using a variant of a Fenwick tree to efficiently manage the concatenated data from all pieces in a data set.  See previously linked design document

## Workflows
Detailed description of key workflows.

### Data Set Creation
1. A client and storage provider agree to set up a data set
2. The storage provider calls the verifier contract to create a new data set
3. The data set is initialized with storage provider permissions and challenge parameters

### Data Verification
1. The storage provider adds Merkle pieces to the data set
2. At each proving period:
   - The system generates random challenges based on chain randomness
   - The storage provider constructs Merkle proofs for the challenged leaves
   - The storage provider submits proofs to the verifier contract
   - The contract verifies the proofs and updates the next challenge epoch

### Fault Handling
1. If a storage provider fails to submit valid proofs within the proving period:
   - The storage provider must call nextProvingPeriod to acknowledge the fault
   - The SimplePDPService contract emits an event registering the fault
   - The system updates the next challenge epoch

## Security Considerations

### Threat Model
- Storage providers may attempt to cheat by not storing data
- Attackers may try to bias randomness or grind data sets
- Data clients could try to force a fault to get out of paying honest storage providers for storage
- Contract ownership could be compromised

### Data Set Independence and Storage Provider Control
- Data set operations are completely independent
- Only the storage provider of a data set can impact the result of operations on that data set

### Soundness
- Proofs are valid only if the storage provider has the challenged data
- Merkle proofs must be sound
- Randomness cannot be biased through grinding or chain forking

### Completeness
- Proving always works if providing Merkle proofs to the randomly sampled leaves

### Liveness
- Storage providers can always add new pieces to the data set
- Progress can be made with nextProvingPeriod after data loss or connectivity issues
- Pieces can be deleted from data sets

### Access Control
- Storage provider management is strictly enforced
- Only data set storage providers can modify their data sets

### Randomness Handling
- Challenge seed generation uses filecoin L1 chain randomness from the drand beacon
- A new FEVM precompile has recently been introduced allowed lookup of drand randomness for any epoch in the past.

## Performance Considerations

### Gas Optimization
- The singleton contract design may have higher costs as state grows
- Merkle proof verification is designed to be gas-efficient

### Scalability
- The system can handle multiple data sets for many storage providers
- The logical array implements binary search using a Fenwick/BIT tree variant that makes efficiency possible for mutating data sets.

## Future Enhancements

### Upgradability
- Proxy pattern implementation
- Version management

### Additional Features
- Planned enhancements
- Roadmap

### Glossary
- **Data Set**: A container for Merkle pieces representing data to be proven
- **Merkle Proof**: A cryptographic proof of data inclusion in a Merkle tree
- **Proving Period**: The time window between successive challenge windows
- **Challenge Window**: The time window during which proofs must be submitted
- **Challenge**: A random request to prove possession of specific data
