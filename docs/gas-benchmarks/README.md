# PDP Gas Benchmarks

This directory contains gas cost benchmarks for PDP.

## Calibration Network Gas Costs

The file `calibration-gas-costs.csv` contains gas cost measurements Calibnet, collected during the week of 2025-03-10 and 2025-03-17. **Operations that was measured was**: 
  - ProvePossession (submitting proofs of data possession)
  - NextProvingPeriod (setting up the next proving window)
  - AddPieces (adding new data pieces to a data set)

## Summary Table

Below is a summary of gas costs by operation type and data characteristics:

| Operation Type | Data Size | Piece Count | Avg Gas Cost | Range |
|---------------|-----------|------------|-------------|-------|
| ProvePossession | 64 GiB | 39 | ~120M | 105-145M |
| ProvePossession | 100 MB | 113 | ~125M | 99-149M |
| ProvePossession | 1 MB | 1011 | ~138M | 123-153M |
| ProvePossession | 1 MB | 10000 | ~177M | 177M |
| NextProvingPeriod | 64 GiB | 39 | ~56M | 56M |
| NextProvingPeriod | 100 MB | 113 | ~54M | 54M |
| NextProvingPeriod | 1 MB | 1011 | ~54M | 54M |
| NextProvingPeriod | 1 MB | 10000 | ~54M | 54M |
| AddPieces | 64 GiB | 39 | ~44M | 44M |
| AddPieces | 100 MB | 113 | ~55M | 55M |
| AddPieces | 1 MB | 1011 | ~81M | 81M |
| AddPieces | 1 MB | 10000 | ~98M | 98M |

## Observations

- **ProvePossession** operations are the most gas-intensive, with costs influenced by a combination of data set size and piece count. The correlation isn't as strong because costs are influenced by a linear combination of two different logarithmic functions: log(# pieces) + log(data set size).
- **NextProvingPeriod** operations have relatively consistent gas costs regardless of data set characteristics.
- **AddPieces** operations show a clear correlation between piece count and gas cost, with costs scaling logarithmically with the number of pieces.

![ProvePossession Gas for DataSet Size](ProvePosession%20Gas%20by%20DataSet%20Size.png)

![AddPieces Gas by DataSet Size](AddPieces%20Gas%20by%20DataSet%20Size.png)

## Raw Data

For detailed transaction information, refer to the [`calibration-gas-costs.csv`](calibration-gas-costs.csv) file which contains links to the specific transactions on calibnet. 