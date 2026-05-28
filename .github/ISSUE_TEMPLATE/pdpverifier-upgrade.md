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

## Rollout Status

| Network | Announced | Executable on or after | Executed | Notes |
| --- | --- | --- | --- | --- |
| Calibration | Pending | TBD | Pending | Upgrade first; fill in the planned-upgrade transaction and timestamp when announced. |
| Mainnet | Pending | TBD | Pending | Upgrade after Calibration execution and smoke tests pass. |

## Operational Notes

- Use this single issue to track the full rollout across both networks.
- Confirm the live proxy `VERSION()` separately; it may lag the release baseline if recent releases did not include a PDPVerifier deployment.
- Record major steps as issue comments as you go rather than editing every detail into the top post.
- The live proxy already supports planned upgrades, first use `tools/announce-planned-upgrade.sh`, wait until the announced epoch, then use `tools/upgrade.sh`.
- Do not deploy until all bytecode-affecting PRs are merged to `main`.
- If the release tag must match the exact on-chain bytecode, tag the deploy commit before changelog-only closeout changes. Otherwise, tag the finalized release-notes commit and record the implementation deploy commit separately.
- The current `tools/deploy-calibnet.sh` and `tools/deploy-mainnet.sh` also deploy a fresh proxy. For upgrades, the safest path is still:
  - deploy the implementation manually with `forge create`
  - generate SAFE calldata with `tools/upgrade.sh`
- `tools/upgrade.sh` prints the SAFE contract's on-chain nonce. The Safe UI may queue the transaction at a higher nonce if there are already pending transactions. That does not change the contract calldata.

Suggested release tag:
- `vX.Y.Z`

## Network Constants

- Mainnet proxy: `0xBADd0B92C1c71d02E7d520f64c0876538fa2557F`
- Calibration proxy: `0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C`
- SAFE owner: `0x3569b2600877a9F42d9Ebdd205386F3F3788F3E5`
- Mainnet RPC: `https://api.node.glif.io/rpc/v1`
- Calibration RPC: `https://api.calibration.node.glif.io/rpc/v1`
- Default planned-upgrade notice window: `2880` epochs (~1 day at 30 seconds/epoch)

## Release Preparation

### 1. Prepare and Merge Release PRs

- [ ] Release-prep PR opened and reviewed
  - Include the `PDPVerifier.VERSION` bump if the deployed contract version is changing.
  - Draft `CHANGELOG.md` release notes before deployment.
  - Use `## [X.Y.Z] - TBD` until the rollout executes.
  - Leave implementation addresses, verification links, and deployment transactions as `TBD` until known.
  - Include expected integration impact, constructor values, and any required caller changes before starting Calibration.
  - Suggested PR title: `docs(changelog): draft vX.Y.Z release notes and version bump`
- [ ] Release-prep PR merged to `main`
  - Any `PDPVerifier.VERSION` bump is bytecode-affecting and must be merged before selecting the deploy commit or deploying any implementation.

### 2. Freeze the Deploy Commit

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

### 3. Confirm Constructor Values

- [ ] Calibration constructor values confirmed
  - [ ] `initializerVersion`
  - [ ] `challengeFinality`
- [ ] Current Calibration proxy initializer counter read

```bash
RPC_URL="https://api.calibration.node.glif.io/rpc/v1" \
./tools/get-initialized-counter.sh 0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C
```

- [ ] Mainnet constructor values confirmed
  - [ ] `initializerVersion`
  - [ ] `challengeFinality`
- [ ] Current Mainnet proxy initializer counter read

```bash
RPC_URL="https://api.node.glif.io/rpc/v1" \
./tools/get-initialized-counter.sh 0xBADd0B92C1c71d02E7d520f64c0876538fa2557F
```

Deploy the next implementation with `initializerVersion = <current counter + 1>`.

### 4. Confirm the Live Proxy Owner and Version

- [ ] Current Calibration proxy owner confirmed
- [ ] Current Calibration proxy version confirmed
- [ ] Current Calibration planned-upgrade slot checked

```bash
cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  -f 0x0000000000000000000000000000000000000000 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "owner()(address)"

cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "VERSION()(string)"

cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "nextUpgrade()(address,uint96)"
```

- [ ] Current Mainnet proxy owner confirmed
- [ ] Current Mainnet proxy version confirmed
- [ ] Current Mainnet planned-upgrade slot checked

```bash
cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  -f 0x0000000000000000000000000000000000000000 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "owner()(address)"

cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "VERSION()(string)"

cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "nextUpgrade()(address,uint96)"
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
  <initializerVersion> \
  10
```

- [ ] Sanity-check `VERSION()` and immutable values on the Calibration implementation

```bash
cast call --rpc-url "$RPC_URL" <IMPL> "VERSION()(string)"
cast call --rpc-url "$RPC_URL" <IMPL> "getChallengeFinality()(uint256)"
```

- [ ] Verify the Calibration implementation on Sourcify
- [ ] Verify the Calibration implementation on Blockscout
- [ ] Verify the Calibration implementation on Filfox (optional)

```bash
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(uint64,uint256)" \
  <initializerVersion> \
  10 | sed 's/^0x//')

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

- [ ] Calibration planned-upgrade announcement payload generated

Choose an `AFTER_EPOCH` that satisfies the required notice window and will still be in the future when the Safe transaction executes. The default notice window is `2880` Filecoin epochs (~1 day); adjust intentionally if the release needs a longer window.

```bash
CURRENT=$(cast block-number --rpc-url "$RPC_URL")
NOTICE_EPOCHS=2880
AFTER_EPOCH=$((CURRENT + NOTICE_EPOCHS))

RPC_URL="$RPC_URL" \
SAFE_ADDRESS="0x3569b2600877a9F42d9Ebdd205386F3F3788F3E5" \
PDP_VERIFIER_PROXY_ADDRESS="0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C" \
NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS="<IMPL>" \
AFTER_EPOCH="$AFTER_EPOCH" \
./tools/announce-planned-upgrade.sh
```

If the Safe UI asks whether to use the implementation ABI for the proxy, use the implementation ABI, but keep the transaction target as the proxy.

- [ ] Stage the Calibration planned-upgrade SAFE transaction
- [ ] Execute the Calibration planned-upgrade SAFE transaction
- [ ] Record the Calibration planned-upgrade announcement transaction hash and update the rollout status table
- [ ] Confirm `nextUpgrade()` matches `<IMPL>` and `AFTER_EPOCH`
- [ ] Wait until the chain reaches `AFTER_EPOCH`

Optional parallel work while waiting: deploy and verify the Mainnet implementation, then stage the Mainnet planned-upgrade announcement with an `AFTER_EPOCH` after the Calibration window. Do not generate, stage, or execute the final Mainnet `upgradeToAndCall` payload until the Calibration upgrade executes and smoke tests pass.

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
- [ ] Confirm `nextUpgrade()` still matches `<IMPL>` and `AFTER_EPOCH`
- [ ] Confirm current epoch is greater than or equal to `AFTER_EPOCH`
- [ ] Execute the Calibration SAFE upgrade transaction in the Safe UI
- [ ] Verify the Calibration proxy implementation slot
- [ ] Verify the Calibration proxy is on `vX.Y.Z`
- [ ] Verify `nextUpgrade()` cleared to the zero address and `0`

```bash
cast rpc --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  eth_getStorageAt \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
  latest | sed 's/"//g' | sed 's/0x000000000000000000000000/0x/'

cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "VERSION()(string)"

cast call --rpc-url https://api.calibration.node.glif.io/rpc/v1 \
  0x85e366Cf9DD2c0aE37E963d9556F5f4718d6417C \
  "nextUpgrade()(address,uint96)"
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

- [ ] Record Calibration result in an issue comment; send external update if needed
  - If release notes need to be drafted or refreshed first: `docs(changelog): draft vX.Y.Z release notes`
- [ ] Confirm no blocker remains for Mainnet rollout

## Mainnet Rollout

- [ ] Calibration rollout completed successfully, including smoke tests
- [ ] Send rollout communication if not already covered by the planned-upgrade announcement
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
  <initializerVersion> \
  150
```

- [ ] Sanity-check `VERSION()` and immutable values on the Mainnet implementation

```bash
cast call --rpc-url "$RPC_URL" <IMPL> "VERSION()(string)"
cast call --rpc-url "$RPC_URL" <IMPL> "getChallengeFinality()(uint256)"
```

- [ ] Verify the Mainnet implementation on Sourcify
- [ ] Verify the Mainnet implementation on Blockscout
- [ ] Verify the Mainnet implementation on Filfox (optional)

```bash
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(uint64,uint256)" \
  <initializerVersion> \
  150 | sed 's/^0x//')

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

- [ ] Mainnet planned-upgrade announcement payload generated

Choose an `AFTER_EPOCH` that satisfies the required notice window and will still be in the future when the Safe transaction executes. The default notice window is `2880` Filecoin epochs (~1 day); adjust intentionally if the release needs a longer window.

```bash
CURRENT=$(cast block-number --rpc-url "$RPC_URL")
NOTICE_EPOCHS=2880
AFTER_EPOCH=$((CURRENT + NOTICE_EPOCHS))

RPC_URL="$RPC_URL" \
SAFE_ADDRESS="0x3569b2600877a9F42d9Ebdd205386F3F3788F3E5" \
PDP_VERIFIER_PROXY_ADDRESS="0xBADd0B92C1c71d02E7d520f64c0876538fa2557F" \
NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS="<IMPL>" \
AFTER_EPOCH="$AFTER_EPOCH" \
./tools/announce-planned-upgrade.sh
```

If the Safe UI asks whether to use the implementation ABI for the proxy, use the implementation ABI, but keep the transaction target as the proxy.

- [ ] Stage the Mainnet planned-upgrade SAFE transaction
- [ ] Execute the Mainnet planned-upgrade SAFE transaction
- [ ] Record the Mainnet planned-upgrade announcement transaction hash and update the rollout status table
- [ ] Confirm `nextUpgrade()` matches `<IMPL>` and `AFTER_EPOCH`
- [ ] Wait until the chain reaches `AFTER_EPOCH`

- [ ] Confirm Calibration upgrade and smoke tests completed successfully before proceeding to final Mainnet upgrade execution

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
- [ ] Confirm `nextUpgrade()` still matches `<IMPL>` and `AFTER_EPOCH`
- [ ] Confirm current epoch is greater than or equal to `AFTER_EPOCH`
- [ ] Execute the Mainnet SAFE upgrade transaction
- [ ] Verify the Mainnet proxy implementation slot
- [ ] Verify the Mainnet proxy is on `vX.Y.Z`
- [ ] Verify `nextUpgrade()` cleared to the zero address and `0`

```bash
cast rpc --rpc-url https://api.node.glif.io/rpc/v1 \
  eth_getStorageAt \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
  latest | sed 's/"//g' | sed 's/0x000000000000000000000000/0x/'

cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "VERSION()(string)"

cast call --rpc-url https://api.node.glif.io/rpc/v1 \
  0xBADd0B92C1c71d02E7d520f64c0876538fa2557F \
  "nextUpgrade()(address,uint96)"
```

- [ ] Publish completion/update communication

## Release Closeout

- [ ] Update `CHANGELOG.md` release date, deployed addresses, verification links, and deployment transactions
- [ ] Final release-note PR merged to `main`
  - Suggested PR title: `docs(changelog): finalize vX.Y.Z release notes`
- [ ] Tag `vX.Y.Z`
  - The tag may point at a changelog-only commit after deployment.
  - Record the implementation deploy commit separately if it differs from the tag commit.

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

- Prefer Blockscout links in the deployed-address section because they give a better verification view than Filfox.
- [ ] Sync PDPVerifier source, ABI, and deployments in `filecoin-services`
  - Pin `service_contracts/lib/pdp` to the exact PDP release tag.
  - Regenerate/check the PDPVerifier ABI if needed.
  - Update implementation addresses in deployment references.
  - Update proxy addresses only if a proxy address actually changed.
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
- Planned-upgrade announcement transaction hash:
- Constructor values:
  - `initializerVersion`:
  - `challengeFinality`:
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
- Planned-upgrade announcement transaction hash:
- Constructor values:
  - `initializerVersion`:
  - `challengeFinality`:
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
