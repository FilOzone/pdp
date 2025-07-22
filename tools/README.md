A place for all tools related to running and developing the PDP contracts. When adding a tool please fill in a description.

# Tools

## Deployment Scripts

### deploy-devnet.sh
Deploys PDPVerifier to a local filecoin devnet. Assumes lotus binary is in path and local devnet is running with eth API enabled. The keystore will be funded automatically from lotus default address.

### deploy-calibnet.sh
Deploys PDPVerifier to Filecoin Calibration testnet.

### deploy-mainnet.sh  
Deploys PDPVerifier to Filecoin mainnet.

### deploy-simple-pdp-service.sh ⚠️ DEPRECATED
**As of v2.0.0, SimplePDPService is deprecated.** This optional script allows deployment of SimplePDPService for reference/community use only. Requires an existing PDPVerifier deployment. See `DEPRECATION.md` for details.

## Upgrade Scripts

### upgrade-contract-calibnet.sh
Generic script for upgrading proxy contracts on Calibration testnet.

### deploy-transfer-ownership-upgrade-calibnet.sh
Deploys, upgrades, and transfers ownership of PDPVerifier on Calibration testnet.

## PDP Interaction Scripts
We have some scripts for interacting with the PDP service contract through ETH RPC API: 
- add.sh
- remove.sh
- create_data_set.sh
- find.sh 
- size.sh

To use these scripts set the following environment variables:
- KEYSTORE
- PASSWORD
- RPC_URL

with values corresponding to local geth keystore path, the password for the keystore and the RPC URL for the network where PDP service contract is deployed. 
