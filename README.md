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

#### v3.1.0 - https://github.com/FilOzone/pdp/releases/tag/v3.1.0

**Mainnet:**
- PDPVerifier Implementation: [0xe2Dc211BffcA499761570E04e8143Be2BA66095f](https:/filfox.info/en/address/0xe2Dc211BffcA499761570E04e8143Be2BA66095f)
- PDPVerifier Proxy: [0xBADd0B92C1c71d02E7d520f64c0876538fa2557F](https://filfox.info/en/address/0xBADd0B92C1c71d02E7d520f64c0876538fa2557F)

**Calibnet:**
- PDPVerifier Implementation: [0x2355Cb19BA1eFF51673562E1a5fc5eE292AF9D42](https://calibration.filfox.info/en/address/0x2355Cb19BA1eFF51673562E1a5fc5eE292AF9D42)
- PDPVerifier Proxy: [0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C](https://calibration.filfox.info/en/address/0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C)

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
