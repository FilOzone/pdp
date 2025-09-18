# Provable Data Possession (PDP) - Service Contract and Tools

## Table of Contents
- [Overview](#overview)
- [Build](#build)
- [Test](#test)
- [Deploy](#deploy)
- [Design Documentation](#design-documentation)
- [Security Audits](#security-audits)
- [Contributing](#contributing)
- [License](#license)

## Overview
This project contains the implementation of the PDP service contract, auxiliary contracts, and development tools for the Provable Data Possession protocol.

### Contracts

The PDP service contract and the PDP verifier contracts are deployed on Filecoin Mainnet and Calibration Testnet.

> Disclaimer: ⚠️ These contracts are still in beta testing and might be upgraded for bug fixes and/or improvements. Please use with caution for production environments. ⚠️

#### v2.1.0

**Mainnet:**
- PDPVerifier Implementation: [0xf2a47b4136Ab2dfB6FA67Fb85c7a031f56F6f024](https://filfox.info/en/address/0xf2a47b4136Ab2dfB6FA67Fb85c7a031f56F6f024)
- PDPVerifier Proxy: [0x31D87004Fc0C38D897725978e51BC06163603E5A](https://filfox.info/en/address/0x31D87004Fc0C38D897725978e51BC06163603E5A)

**Calibnet:**
- PDPVerifier Implementation: [0x648E8D9103Ec91542DcD0045A65Ef9679F886e82](https://calibration.filfox.info/en/address/0x648E8D9103Ec91542DcD0045A65Ef9679F886e82)
- PDPVerifier Proxy: [0x445238Eca6c6aB8Dff1Aa6087d9c05734D22f137](https://calibration.filfox.info/en/address/0x445238Eca6c6aB8Dff1Aa6087d9c05734D22f137)

#### v1.1.0

⚠️ Deprecation Notice: The following contracts will be deprecated (read-only) by End of August. Please upgrade/migrate to the latest contracts as soon as they are available.

**Mainnet**
- [PDP Verifier]([url](https://github.com/FilOzone/pdp/blob/main/src/PDPVerifier.sol)): [0x9C65E8E57C98cCc040A3d825556832EA1e9f4Df6]([url](https://filfox.info/en/address/0x9C65E8E57C98cCc040A3d825556832EA1e9f4Df6))
- [PDP Service]([url](https://github.com/FilOzone/pdp/blob/main/src/SimplePDPService.sol)): [0x805370387fA5Bd8053FD8f7B2da4055B9a4f8019]([url](https://filfox.info/en/address/0x805370387fA5Bd8053FD8f7B2da4055B9a4f8019))

**Calibration Testnet**
- [PDP Verifier]([url](https://github.com/FilOzone/pdp/blob/main/src/PDPVerifier.sol)): [0x5A23b7df87f59A291C26A2A1d684AD03Ce9B68DC]([url](https://calibration.filfox.info/en/address/0x5A23b7df87f59A291C26A2A1d684AD03Ce9B68DC))
- [PDP Service]([url](https://github.com/FilOzone/pdp/blob/main/src/SimplePDPService.sol)): [0x6170dE2b09b404776197485F3dc6c968Ef948505]([url](https://calibration.filfox.info/en/address/0x6170dE2b09b404776197485F3dc6c968Ef948505)) Note this has proving period every 30 minutes instead of every day

## Build
Depends on [Foundry](https://github.com/foundry-rs/foundry) for development.
```
make build
```
## Test
```
make test
```
## Deploy
To deploy on devnet, run:
```
make deploy-devnet
```

To deploy on calibrationnet, run:
```
make deploy-calibnet
```

To deploy on mainnet, run:
```
make deploy-mainnet
```

## Design Documentation
For comprehensive design details, see [DESIGN.md](docs/design.md)

## Security Audits
The PDP contracts have undergone the following security audits:
- [Zellic Security Audit (April 2025)](https://github.com/Zellic/publications/blob/master/Proof%20of%20Data%20Possession%20-%20Zellic%20Audit%20Report.pdf)

## Contributing
Contributions are welcome! Please follow these contribution guidelines:

### Implementing Changes
Follow the existing code style and patterns. Write clear, descriptive commit messages and include relevant tests for new features or bug fixes. Keep changes focused and well-encapsulated, and document any new functionality.

### Pull Requests
Use descriptive PR titles that summarize the change. Include a clear description of the changes and their purpose, reference any related issues, and ensure all tests pass and code is properly linted.

### Getting Help
If you need assistance, feel free to open a issue or reach out to the maintainers of the contract in the #fil-pdp channel on [Filecoin Slack](https://filecoin.io/slack).

## License

Dual-licensed under [MIT](https://github.com/filecoin-project/lotus/blob/master/LICENSE-MIT) + [Apache 2.0](https://github.com/filecoin-project/lotus/blob/master/LICENSE-APACHE)
