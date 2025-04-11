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

> Disclaimer: ⚠️ These contracts are still under alpha testing and might be upgraded for bug fixes and/or improvements. Please use with caution for production environments. ⚠️

**Mainnet**
- [PDP Verifier]([url](https://github.com/FilOzone/pdp/blob/main/src/PDPVerifier.sol)): [0x1285B4D8CA94AD167dB37ac161762ecA8cE7C0dB]([url](https://filfox.info/en/address/0x1285B4D8CA94AD167dB37ac161762ecA8cE7C0dB))
- [PDP Service]([url](https://github.com/FilOzone/pdp/blob/main/src/SimplePDPService.sol)): [0xf47FE41e78d0356471244740B7d57e42E5456891]([url](https://filfox.info/en/address/0xf47FE41e78d0356471244740B7d57e42E5456891))
- [PDP Service Proxy]([url](https://github.com/FilOzone/pdp/blob/main/src/ERC1967Proxy.sol)): [0x805370387fA5Bd8053FD8f7B2da4055B9a4f8019]([url](https://filfox.info/en/address/0x805370387fA5Bd8053FD8f7B2da4055B9a4f8019))

**Calibration Testnet**
- [PDP Verifier]([url](https://github.com/FilOzone/pdp/blob/main/src/PDPVerifier.sol)): [0x159C8b1FBFB7240Db85A1d75cf0B2Cc7C09f932d]([url](https://filfox.info/en/address/0x159C8b1FBFB7240Db85A1d75cf0B2Cc7C09f932d))
- [PDP Service]([url](https://github.com/FilOzone/pdp/blob/main/src/SimplePDPService.sol)): [0x7F0dCeA9D4FB65Cc5801Dc5dfc71b4Ae006484D0]([url](https://filfox.info/en/address/0x7F0dCeA9D4FB65Cc5801Dc5dfc71b4Ae006484D0))

## Build
```
make build 
```
## Test
```
make test
```
## Deploy
To deploy on calibrationnet, run:
```
make deploy-calibrationnet
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
