# PDPVerifier Upgrade Checklist

This document is a maintainer-facing runbook for upgrading the deployed `PDPVerifier` proxy on Calibration and Mainnet.

It is based on the `v3.1.0 -> v3.2.0` rollout and is intended to be followed manually.

## Scope

Use this checklist when:
- deploying a new `PDPVerifier` implementation
- upgrading the existing proxy on Calibration
- upgrading the existing proxy on Mainnet
- preparing release notes and post-release follow-up tasks

Do not use this document for first-time proxy deployments. This is only for upgrading an existing proxy.

## Naming Conventions

Suggested issue titles:
- `Calibnet: PDPVerifier upgrade from \`vA.B.C\` to \`vX.Y.Z\``
- `Mainnet: PDPVerifier upgrade from \`vA.B.C\` to \`vX.Y.Z\``

Suggested PR titles:
- Changelog draft: `docs(changelog): draft vX.Y.Z release notes`
- Changelog finalization: `docs(changelog): finalize vX.Y.Z release notes`
- SAFE/tooling updates: `tools: support SAFE-owned PDP upgrades`
- Constructor/deploy script updates: `tools: update PDPVerifier deploy scripts for 4-arg constructor`
- Version fix: `chore: correctly set version to vX.Y.Z`
- Runbook update: `docs: add PDPVerifier upgrade checklist`

Suggested release tag:
- `vX.Y.Z`

## Important Notes

- Do not deploy an implementation until all bytecode-affecting PRs are merged to `main`.
- Tooling-only or docs-only PRs do not change the deployed bytecode.
- Tag the exact deployed commit first if you want the git tag to match the on-chain bytecode exactly.
- If changelog-only updates happen after deploy, commit them after tagging.
- The current `tools/deploy-calibnet.sh` and `tools/deploy-mainnet.sh` also deploy a fresh proxy. For upgrades, the safest path is still:
  - deploy the implementation manually with `forge create`
  - generate SAFE calldata with `tools/upgrade.sh`
- `tools/upgrade.sh` prints the SAFE contract's on-chain nonce. The Safe UI may queue the transaction at a higher nonce if there are already pending transactions. That does not change the contract calldata.

## One-Step vs Two-Step Upgrades

The upgrade flow depends on the currently deployed proxy version:

- If the live proxy predates `announcePlannedUpgrade()` and `nextUpgrade()`:
  - use the legacy one-step upgrade flow
  - `tools/upgrade.sh` will print calldata for `upgradeToAndCall(address,bytes)`
- If the live proxy already supports planned upgrades:
  - first use `tools/announce-planned-upgrade.sh`
  - wait until the announced epoch
  - then use `tools/upgrade.sh`

For the `v3.1.0 -> v3.2.0` rollout, both Calibration and Mainnet were still on the legacy one-step path.

## Network Constants

Current PDPVerifier proxies:

- Mainnet proxy: `0xBADd0B92C1c71d02E7d520f64c0876538fa2557F`
- Calibration proxy: `0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C`

Current SAFE owner used in the `v3.2.0` rollout:

- SAFE owner: `0x3569b2600877a9F42d9Ebdd205386F3F3788F3E5`

Current RPC endpoints:

- Mainnet: `https://api.node.glif.io/rpc/v1`
- Calibration: `https://api.calibration.node.glif.io/rpc/v1`

## Release Preparation

### 1. Create Tracking Issues

Create two issues:
- one for Calibration
- one for Mainnet

Use the issue body to track:
- deploy commit
- constructor values
- implementation addresses
- verification links
- SAFE transaction link
- execution window
- post-upgrade verification

Mainnet should depend on Calibration finishing first.

<a id="freeze-deploy-commit"></a>
### 2. Freeze the Deploy Commit

From the repo root:

```bash
git checkout main
git pull --ff-only origin main
git rev-parse HEAD
```

Record that commit hash in both upgrade issues.

Before proceeding, verify the contract version you intend to deploy:

```bash
rg -n 'string public constant VERSION' src/PDPVerifier.sol
```

<a id="confirm-constructor-values"></a>
### 3. Confirm Constructor Values

`PDPVerifier` currently takes a 4-argument constructor:

- `initializerVersion`
- `USDFC_TOKEN_ADDRESS`
- `USDFC_SYBIL_FEE`
- `PAYMENTS_CONTRACT_ADDRESS`

The `initializerVersion` is the current initialized counter plus `1`.

Read it from the live proxy:

Calibration:

```bash
RPC_URL="https://api.calibration.node.glif.io/rpc/v1" \
./tools/get-initialized-counter.sh 0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C
```

Mainnet:

```bash
RPC_URL="https://api.node.glif.io/rpc/v1" \
./tools/get-initialized-counter.sh 0xBADd0B92C1c71d02E7d520f64c0876538fa2557F
```

If the command returns `1`, deploy the next implementation with `initializerVersion = 2`.

<a id="confirm-live-proxy-owner-and-version"></a>
### 4. Confirm the Live Proxy Owner and Version

Calibration:

```bash
cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  -f 0x0000000000000000000000000000000000000000 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "owner()(address)"

cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "VERSION()(string)"
```

Mainnet:

```bash
cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  -f 0x0000000000000000000000000000000000000000 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "owner()(address)"

cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "VERSION()(string)"
```

If the owner is a SAFE or other contract owner, use `tools/upgrade.sh` to generate calldata for the owner workflow rather than broadcasting directly.

## Calibration Rollout

<a id="calibration-deploy-implementation"></a>
### 5. Deploy the New Implementation

The safest path is manual `forge create`.

Calibration example:

```bash
export RPC_URL="https://api.calibration.node.glif.io/rpc/v1"
export KEYSTORE="..."
export PASSWORD="..."

forge create \
  --rpc-url "$RPC_URL" \
  --keystore "$KEYSTORE" \
  --password "$PASSWORD" \
  --broadcast \
  --chain-id 314159 \
  src/PDPVerifier.sol:PDPVerifier \
  --constructor-args \
  2 \
  0xb3042734b608a1B16e9e86B374A3f3e389B4cDf0 \
  100000000000000000 \
  0x09a0fDc2723fAd1A7b8e3e00eE5DF73841df55a0
```

Record:
- deployer address
- implementation address
- deployment transaction hash

<a id="calibration-sanity-check-implementation"></a>
### 6. Sanity-Check the Implementation

Replace `<IMPL>` with the deployed implementation address.

```bash
cast call --rpc-url "$RPC_URL" <IMPL> "VERSION()(string)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_TOKEN_ADDRESS()(address)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_SYBIL_FEE()(uint256)"
cast call --rpc-url "$RPC_URL" <IMPL> "PAYMENTS_CONTRACT_ADDRESS()(address)"
```

These values must match the intended release before continuing.

<a id="calibration-verify-implementation"></a>
### 7. Verify the Implementation on Explorers

Sourcify:

```bash
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(uint64,address,uint256,address)" \
  2 \
  0xb3042734b608a1B16e9e86B374A3f3e389B4cDf0 \
  100000000000000000 \
  0x09a0fDc2723fAd1A7b8e3e00eE5DF73841df55a0 | sed 's/^0x//')

forge verify-contract \
  --chain 314159 \
  --rpc-url "$RPC_URL" \
  --watch \
  --constructor-args "$CONSTRUCTOR_ARGS" \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier
```

Blockscout:

```bash
forge verify-contract \
  --chain-id 314159 \
  --verifier blockscout \
  --verifier-url "https://filecoin-testnet.blockscout.com/api/" \
  --force \
  --skip-is-verified-check \
  --watch \
  --constructor-args "$CONSTRUCTOR_ARGS" \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier
```

Filfox:

```bash
filfox-verifier forge \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier \
  --chain 314159
```

<a id="calibration-generate-safe-payload"></a>
### 8. Generate the SAFE Upgrade Payload

```bash
ETH_RPC_URL="$RPC_URL" \
SAFE_ADDRESS="0x3569b2600877a9F42d9Ebdd205386F3F3788F3E5" \
PDP_VERIFIER_PROXY_ADDRESS="0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C" \
NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS="<IMPL>" \
./tools/upgrade.sh
```

For legacy one-step upgrades, this prints:
- `target`
- `value`
- `data`

If building the transaction via the Safe UI ABI form:
- method: `upgradeToAndCall(address,bytes)`
- `newImplementation`: `<IMPL>`
- `data`: `0x8fd3ab80`

`0x8fd3ab80` is the calldata for `migrate()`.

<a id="calibration-independent-review"></a>
### 9. Ask for Independent Review

Before asking signers to approve:
- share the SAFE transaction link
- share the implementation address
- share the verification links
- ask for an independent review of the calldata and implementation

<a id="calibration-execute-upgrade"></a>
### 10. Execute the Calibration Upgrade

Submit via the Safe UI.

After execution, verify:

```bash
cast rpc --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  eth_getStorageAt \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
  latest | sed 's/"//g' | sed 's/0x000000000000000000000000/0x/'

cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "VERSION()(string)"
```

<a id="calibration-smoke-tests"></a>
### 11. Run Lightweight Smoke Tests

Read-only smoke tests are enough for a first post-upgrade check.

Find a recent live dataset with active pieces:

```bash
RPC_URL="https://api.calibration.node.glif.io/rpc/v1"
PROXY="0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C"
NEXT=$(cast call --rpc-url "$RPC_URL" "$PROXY" "getNextDataSetId()(uint256)" | awk '{print $1}')

for id in $(seq $((NEXT-1)) -1 $((NEXT-20))); do
  live=$(cast call --rpc-url "$RPC_URL" "$PROXY" "dataSetLive(uint256)(bool)" "$id" 2>/dev/null || true)
  if [ "$live" = "true" ]; then
    active=$(cast call --rpc-url "$RPC_URL" "$PROXY" "getActivePieceCount(uint256)(uint256)" "$id" 2>/dev/null | awk '{print $1}' || true)
    if [ "$active" != "0" ]; then
      echo "SET_ID=$id ACTIVE=$active"
      break
    fi
  fi
done
```

Then run:

```bash
SET_ID=<live_set_id>
CID=$(cast call --rpc-url "$RPC_URL" "$PROXY" "getPieceCid(uint256,uint256)((bytes))" "$SET_ID" 0 | tr -d '()')

cast call --rpc-url "$RPC_URL" "$PROXY" \
  "getActivePieces(uint256,uint256,uint256)((bytes)[],uint256[],bool)" \
  "$SET_ID" 0 10

cast call --rpc-url "$RPC_URL" "$PROXY" \
  "getActivePiecesByCursor(uint256,uint256,uint256)((bytes)[],uint256[],bool)" \
  "$SET_ID" 0 10

cast call --rpc-url "$RPC_URL" "$PROXY" \
  "findPieceIdsByCid(uint256,(bytes),uint256,uint256)(uint256[])" \
  "$SET_ID" "($CID)" 0 10
```

Check that:
- the old and new pagination calls agree
- `findPieceIdsByCid()` returns the expected piece ID(s)

## Mainnet Rollout

Repeat the same process after Calibration succeeds.

<a id="mainnet-deploy-implementation"></a>
### 12. Deploy the Mainnet Implementation

```bash
export RPC_URL="https://api.node.glif.io/rpc/v1"
export KEYSTORE="..."
export PASSWORD="..."

forge create \
  --rpc-url "$RPC_URL" \
  --keystore "$KEYSTORE" \
  --password "$PASSWORD" \
  --broadcast \
  --chain-id 314 \
  src/PDPVerifier.sol:PDPVerifier \
  --constructor-args \
  2 \
  0x80B98d3aa09ffff255c3ba4A241111Ff1262F045 \
  100000000000000000 \
  0x23b1e018F08BB982348b15a86ee926eEBf7F4DAa
```

<a id="mainnet-sanity-check-implementation"></a>
### 13. Sanity-Check the Mainnet Implementation

```bash
cast call --rpc-url "$RPC_URL" <IMPL> "VERSION()(string)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_TOKEN_ADDRESS()(address)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_SYBIL_FEE()(uint256)"
cast call --rpc-url "$RPC_URL" <IMPL> "PAYMENTS_CONTRACT_ADDRESS()(address)"
```

<a id="mainnet-verify-implementation"></a>
### 14. Verify the Mainnet Implementation

Sourcify:

```bash
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(uint64,address,uint256,address)" \
  2 \
  0x80B98d3aa09ffff255c3ba4A241111Ff1262F045 \
  100000000000000000 \
  0x23b1e018F08BB982348b15a86ee926eEBf7F4DAa | sed 's/^0x//')

forge verify-contract \
  --chain 314 \
  --rpc-url "$RPC_URL" \
  --watch \
  --constructor-args "$CONSTRUCTOR_ARGS" \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier
```

Blockscout:

```bash
forge verify-contract \
  --chain-id 314 \
  --verifier blockscout \
  --verifier-url "https://filecoin.blockscout.com/api/" \
  --force \
  --skip-is-verified-check \
  --watch \
  --constructor-args "$CONSTRUCTOR_ARGS" \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier
```

Filfox:

```bash
filfox-verifier forge \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier \
  --chain 314
```

<a id="mainnet-generate-safe-payload"></a>
### 15. Generate the Mainnet SAFE Payload

```bash
ETH_RPC_URL="$RPC_URL" \
SAFE_ADDRESS="0x3569b2600877a9F42d9Ebdd205386F3F3788F3E5" \
PDP_VERIFIER_PROXY_ADDRESS="0xBADd0B92C1c71d02E7d520f64c0876538fa2557F" \
NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS="<IMPL>" \
./tools/upgrade.sh
```

If building the Safe transaction with ABI inputs:
- method: `upgradeToAndCall(address,bytes)`
- `newImplementation`: `<IMPL>`
- `data`: `0x8fd3ab80`

<a id="mainnet-independent-review"></a>
### 16. Independent Review and Signer Approval

Before execution:
- get an independent review of the transaction
- then ask SAFE signers to approve it

<a id="mainnet-execute-upgrade"></a>
### 17. Execute the Mainnet Upgrade

After execution, verify:

```bash
cast rpc --rpc-url https://api.node.glif.io/rpc/v1 \
  eth_getStorageAt \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
  latest | sed 's/"//g' | sed 's/0x000000000000000000000000/0x/'

cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "VERSION()(string)"
```

## Release Closeout

<a id="tag-deployed-commit"></a>
### 18. Tag the Deployed Commit

If the deployed bytecode came from `main`, tag that exact commit before making changelog-only follow-up edits:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

<a id="finalize-changelog"></a>
### 19. Finalize `CHANGELOG.md`

Update:
- the release date
- deployed implementation and proxy addresses for both networks
- any contract-code PRs that landed after the initial draft

Prefer Blockscout links in the deployed-address section because they give a better verification view than Filfox.

### 20. Publish Completion Comms

Post:
- Calibration upgrade complete
- Mainnet upgrade complete
- execution transaction link
- proxy unchanged
- new version now live
- no user action required

### 21. Close the Tracking Issues

Each issue should end with:
- deploy commit
- implementation address
- verification links
- SAFE transaction link
- execution transaction link
- post-upgrade verification commands and results
- smoke-test result summary

## Post-Release Follow-Ups

After the on-chain upgrade is complete, do the following:

<a id="sync-filecoin-services"></a>
### 22. Sync `filecoin-services`

Sync `PDPVerifier` source, ABI, and deployment addresses in the `filecoin-services` repo.

Example:
- [FilOzone/filecoin-services#447](https://github.com/FilOzone/filecoin-services/pull/447)

Suggested PR title:
- `pdp: sync PDPVerifier vX.Y.Z source, abi, and deployments`

<a id="fwss-subgraph-follow-up"></a>
### 23. Open a `fwss-subgraph` Tracking Issue

Create an issue in `fwss-subgraph` to track any required subgraph updates for the new `PDPVerifier` version.

Example:
- [FIL-Builders/fwss-subgraph#1](https://github.com/FIL-Builders/fwss-subgraph/issues/1)

Suggested issue title:
- `Track PDPVerifier vX.Y.Z upgrade follow-up`

Suggested issue bullets:
- confirm deployed implementation addresses
- confirm proxy addresses remain unchanged
- check whether new ABI fields or functions require subgraph changes
- check whether any new events need indexing
- plan deployment/update timing

## Optional Future Improvement

If the upgrade process is expected to be repeated often, it may be worth adding a dedicated script that:
- deploys an implementation only
- verifies it
- prints the SAFE payload

For now, the manual `forge create` + `tools/upgrade.sh` flow is the least surprising path.
