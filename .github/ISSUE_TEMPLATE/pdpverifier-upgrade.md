---
name: PDPVerifier Upgrade
about: Track a PDPVerifier upgrade rollout across Calibration and Mainnet
title: "PDPVerifier upgrade from `vA.B.C` to `vX.Y.Z`"
labels: ""
assignees: ""
---

## Summary

Track the successive rollout of `PDPVerifier` from `vA.B.C` to `vX.Y.Z`, with Calibration first and Mainnet second.

This issue is the full operational checklist for the rollout and release closeout.

## Operational Notes

- Use this single issue to track the full rollout across both networks.
- Record major steps as issue comments as you go rather than editing every detail into the top post.
- The live proxy already supports planned upgrades, first use `tools/announce-planned-upgrade.sh`, wait until the announced epoch, then use `tools/upgrade.sh`.
- Do not deploy until all bytecode-affecting PRs are merged to `main`.
- Tag the exact deployed commit first if you want the git tag to match the on-chain bytecode exactly.
- If changelog-only updates happen after deploy, commit them after tagging.
- The current `tools/deploy-calibnet.sh` and `tools/deploy-mainnet.sh` also deploy a fresh proxy. For upgrades, the safest path is still:
  - deploy the implementation manually with `forge create`
  - generate SAFE calldata with `tools/upgrade.sh`
- `tools/upgrade.sh` prints the SAFE contract's on-chain nonce. The Safe UI may queue the transaction at a higher nonce if there are already pending transactions. That does not change the contract calldata.

Suggested PR titles:
- Changelog draft: `docs(changelog): draft vX.Y.Z release notes`
- Changelog finalization: `docs(changelog): finalize vX.Y.Z release notes`
- Issue-template update: `docs: update PDPVerifier upgrade issue template`

Suggested release tag:
- `vX.Y.Z`

## Network Constants

- Mainnet proxy: `0xBADd0B92C1c71d02E7d520f64c0876538fa2557F`
- Calibration proxy: `0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C`
- SAFE owner: `0x3569b2600877a9F42d9Ebdd205386F3F3788F3E5`
- Mainnet RPC: `https://api.node.glif.io/rpc/v1`
- Calibration RPC: `https://api.calibration.node.glif.io/rpc/v1`

## Release Preparation

### 1. Freeze the Deploy Commit

- [ ] Final deploy commit on `main` confirmed

```bash
git checkout main
git pull --ff-only origin main
git rev-parse HEAD
```

- [ ] Intended `VERSION` confirmed in `src/PDPVerifier.sol`
  - If a version-only fix PR is needed: `chore: correctly set version to vX.Y.Z`

```bash
rg -n 'string public constant VERSION' src/PDPVerifier.sol
```

### 2. Confirm Constructor Values

- [ ] Calibration constructor values confirmed
  - [ ] `initializerVersion`
  - [ ] `USDFC_TOKEN_ADDRESS`
  - [ ] `USDFC_SYBIL_FEE`
  - [ ] `PAYMENTS_CONTRACT_ADDRESS`
- [ ] Current Calibration proxy initializer counter read

```bash
RPC_URL="https://api.calibration.node.glif.io/rpc/v1" \
./tools/get-initialized-counter.sh 0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C
```

- [ ] Mainnet constructor values confirmed
  - [ ] `initializerVersion`
  - [ ] `USDFC_TOKEN_ADDRESS`
  - [ ] `USDFC_SYBIL_FEE`
  - [ ] `PAYMENTS_CONTRACT_ADDRESS`
- [ ] Current Mainnet proxy initializer counter read

```bash
RPC_URL="https://api.node.glif.io/rpc/v1" \
./tools/get-initialized-counter.sh 0xBADd0B92C1c71d02E7d520f64c0876538fa2557F
```

If the command returns `1`, deploy the next implementation with `initializerVersion = 2`.

### 3. Confirm the Live Proxy Owner and Version

- [ ] Current Calibration proxy owner confirmed
- [ ] Current Calibration proxy version confirmed

```bash
cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  -f 0x0000000000000000000000000000000000000000 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "owner()(address)"

cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "VERSION()(string)"
```

- [ ] Current Mainnet proxy owner confirmed
- [ ] Current Mainnet proxy version confirmed

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

- [ ] Deploy the new `PDPVerifier` implementation to Calibration
  - Record deployer address, implementation address, and deployment transaction hash

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

- [ ] Sanity-check `VERSION()` and immutable values on the Calibration implementation

```bash
cast call --rpc-url "$RPC_URL" <IMPL> "VERSION()(string)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_TOKEN_ADDRESS()(address)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_SYBIL_FEE()(uint256)"
cast call --rpc-url "$RPC_URL" <IMPL> "PAYMENTS_CONTRACT_ADDRESS()(address)"
```

- [ ] Verify the Calibration implementation on Sourcify
- [ ] Verify the Calibration implementation on Blockscout
- [ ] Verify the Calibration implementation on Filfox (optional)

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

filfox-verifier forge \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier \
  --chain 314159
```

- [ ] Calibration SAFE upgrade transaction payload generated
  - If SAFE/contract-owner helper changes are needed first: `tools: support SAFE-owned PDP upgrades`

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

- [ ] Calibration implementation address, verification links, and calldata shared for independent review
- [ ] Stage the Calibration SAFE transaction
- [ ] Confirm the Calibration execution window
- [ ] Execute the Calibration SAFE upgrade transaction in the Safe UI
- [ ] Verify the Calibration proxy implementation slot
- [ ] Verify the Calibration proxy is on `vX.Y.Z`

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

- [ ] Run lightweight read-only smoke tests on Calibration

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

- [ ] Post Calibration completion/update communication
  - If release notes need to be drafted or refreshed first: `docs(changelog): draft vX.Y.Z release notes`
- [ ] Confirm no blocker remains for Mainnet rollout

## Mainnet Rollout

- [ ] Calibration rollout completed successfully
- [ ] Draft and send initial upgrade communication
  - If release notes need to be drafted or refreshed first: `docs(changelog): draft vX.Y.Z release notes`
- [ ] Deploy the new `PDPVerifier` implementation to Mainnet
  - Record deployer address, implementation address, and deployment transaction hash

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

- [ ] Sanity-check `VERSION()` and immutable values on the Mainnet implementation

```bash
cast call --rpc-url "$RPC_URL" <IMPL> "VERSION()(string)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_TOKEN_ADDRESS()(address)"
cast call --rpc-url "$RPC_URL" <IMPL> "USDFC_SYBIL_FEE()(uint256)"
cast call --rpc-url "$RPC_URL" <IMPL> "PAYMENTS_CONTRACT_ADDRESS()(address)"
```

- [ ] Verify the Mainnet implementation on Sourcify
- [ ] Verify the Mainnet implementation on Blockscout
- [ ] Verify the Mainnet implementation on Filfox (optional)

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

filfox-verifier forge \
  <IMPL> \
  src/PDPVerifier.sol:PDPVerifier \
  --chain 314
```

- [ ] Mainnet SAFE upgrade transaction payload generated
  - If SAFE/contract-owner helper changes are needed first: `tools: support SAFE-owned PDP upgrades`

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

- [ ] Mainnet implementation address, verification links, calldata, and rollout notes shared for independent review
- [ ] Stage the Mainnet SAFE transaction
- [ ] Collect SAFE signer approvals
- [ ] Confirm the Mainnet execution date/time
- [ ] Execute the Mainnet SAFE upgrade transaction
- [ ] Verify the Mainnet proxy implementation slot
- [ ] Verify the Mainnet proxy is on `vX.Y.Z`

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

- [ ] Publish completion/update communication

## Release Closeout

- [ ] Tag the deployed commit as `vX.Y.Z`

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

- [ ] Update `CHANGELOG.md` release date and deployed addresses
- [ ] Finalize release notes on `main`
  - Suggested PR title: `docs(changelog): finalize vX.Y.Z release notes`
- Prefer Blockscout links in the deployed-address section because they give a better verification view than Filfox.
- [ ] Sync PDPVerifier source, ABI, and deployments in `filecoin-services`
- [ ] Create follow-up issue in `fwss-subgraph`
- [ ] Close this rollout issue
  - If the issue template needs improvement afterward: `docs: update PDPVerifier upgrade issue template`

## Deployment / Verification Details

Fill these in as comments or update them here once known.

- Deploy commit:
- Release tag:

### Calibration

- Proxy address:
- Previous implementation address:
- New implementation address:
- Deployment transaction hash:
- Constructor values:
  - `initializerVersion`:
  - `USDFC_TOKEN_ADDRESS`:
  - `USDFC_SYBIL_FEE`:
  - `PAYMENTS_CONTRACT_ADDRESS`:
- Verification links:
  - Sourcify:
  - Blockscout:
  - Filfox:
- SAFE transaction link:
- SAFE execution transaction hash:
- Smoke-test commands/results:

### Mainnet

- Proxy address:
- Previous implementation address:
- New implementation address:
- Deployment transaction hash:
- Constructor values:
  - `initializerVersion`:
  - `USDFC_TOKEN_ADDRESS`:
  - `USDFC_SYBIL_FEE`:
  - `PAYMENTS_CONTRACT_ADDRESS`:
- Verification links:
  - Sourcify:
  - Blockscout:
  - Filfox:
- SAFE transaction link:
- SAFE execution transaction hash:

- Upgrade communication links:
- Post-release follow-up links:
  - `filecoin-services` PR:
  - `fwss-subgraph` issue:

## Suggested Comment Cadence

Recommended issue comments to post as the rollout progresses:

1. Deploy commit and Calibration constructor values
2. Calibration implementation deployment output
3. Calibration verification links and SAFE transaction review request
4. Calibration execution transaction link and smoke-test results
5. Mainnet implementation deployment output
6. Mainnet verification links and SAFE transaction review request
7. Scheduled Mainnet execution window
8. Mainnet execution transaction link and post-upgrade verification
9. Release-closeout links (`CHANGELOG`, tag, `filecoin-services`, `fwss-subgraph`)
