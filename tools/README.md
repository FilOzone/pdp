A place for all tools related to running and developing the PDP service contract.  When adding a tool please fill in a description

# Tools

## deploy-devnet.sh
This script deploys the PDP service contract to a local filecoin devnet.  It assumes lotus binary is in path and local devnet is running with eth API enabled.  The keystore will be funded automatically from lotus default address. 

## pdp scripts
We have some scripts for interacting with the PDP service contract through ETH RPC API: 
- add.sh
- remove.sh
- createdataset.sh
- find.sh 
- size.sh

To use these scripts set the following environment variables:
- KEYSTORE
- PASSWORD
- RPC_URL

with values corresponding to local geth keystore path, the password for the keystore and the RPC URL for the network where PDP service contract is deployed. 
