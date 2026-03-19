---
name: PDPVerifier Upgrade
about: Track a PDPVerifier upgrade rollout across Calibration and Mainnet
title: "PDPVerifier upgrade from `vA.B.C` to `vX.Y.Z`"
labels: ""
assignees: ""
---

## Summary

Track the successive rollout of `PDPVerifier` from `vA.B.C` to `vX.Y.Z`, with Calibration first and Mainnet second.

This issue is the operational checklist for the full release rollout and release closeout.

## Notes

- Use this single issue to track the full rollout across both networks.
- Follow the matching sections in `docs/pdpverifier-upgrade-checklist.md`.
- Before starting, record the exact runbook revision or blob URL used for this rollout.
- Record major steps as issue comments as you go rather than editing every detail into the top post.
- If the live proxy predates `announcePlannedUpgrade()`, use the legacy one-step flow and `tools/upgrade.sh`.
- Do not deploy until all bytecode-affecting PRs are merged to `main`.

## Preconditions

- [ ] Runbook revision/blob URL recorded below
- [ ] Final deploy commit on `main` confirmed
- [ ] Final release version confirmed in `src/PDPVerifier.sol`
  - If a version-only fix PR is needed: `chore: correctly set version to vX.Y.Z`

## Checklist

### Release Input

- [ ] Confirm the exact git commit on `main` to deploy
- [ ] Confirm the intended `VERSION` in `src/PDPVerifier.sol`
- [ ] Confirm Calibration constructor values
  - [ ] `initializerVersion`
  - [ ] `USDFC_TOKEN_ADDRESS`
  - [ ] `USDFC_SYBIL_FEE`
  - [ ] `PAYMENTS_CONTRACT_ADDRESS`
- [ ] Read the current Calibration proxy initializer counter
- [ ] Confirm the current Calibration proxy owner
- [ ] Confirm the current Calibration proxy version

### Calibration Rollout

- [ ] Deploy the new `PDPVerifier` implementation to Calibration
- [ ] Verify the Calibration implementation on Sourcify
- [ ] Verify the Calibration implementation on Blockscout
- [ ] Verify the Calibration implementation on Filfox (optional)
- [ ] Sanity-check `VERSION()` and immutable values on the Calibration implementation
- [ ] Generate the Calibration SAFE upgrade transaction payload
  - If SAFE/contract-owner helper changes are needed first: `tools: support SAFE-owned PDP upgrades`
- [ ] Share the Calibration implementation address, verification links, and calldata for independent review
- [ ] Stage the Calibration SAFE transaction
- [ ] Confirm the Calibration execution window
- [ ] Execute the Calibration SAFE upgrade transaction
- [ ] Verify the Calibration proxy implementation slot
- [ ] Verify the Calibration proxy is on `vX.Y.Z`
- [ ] Run lightweight read-only smoke tests on Calibration
- [ ] Post Calibration completion/update communication
  - If release notes need to be drafted or refreshed first: `docs(changelog): draft vX.Y.Z release notes`
- [ ] Confirm no blocker remains for Mainnet rollout

### Mainnet Rollout

- [ ] Calibration rollout completed successfully
- [ ] Confirm Mainnet constructor values
  - [ ] `initializerVersion`
  - [ ] `USDFC_TOKEN_ADDRESS`
  - [ ] `USDFC_SYBIL_FEE`
  - [ ] `PAYMENTS_CONTRACT_ADDRESS`
- [ ] Read the current Mainnet proxy initializer counter
- [ ] Confirm the current Mainnet proxy owner
- [ ] Confirm the current Mainnet proxy version
- [ ] Draft and send initial upgrade communication
  - If release notes need to be drafted or refreshed first: `docs(changelog): draft vX.Y.Z release notes`
- [ ] Deploy the new `PDPVerifier` implementation to Mainnet
- [ ] Verify the Mainnet implementation on Sourcify
- [ ] Verify the Mainnet implementation on Blockscout
- [ ] Verify the Mainnet implementation on Filfox (optional)
- [ ] Sanity-check `VERSION()` and immutable values on the Mainnet implementation
- [ ] Generate the Mainnet SAFE upgrade transaction payload
  - If SAFE/contract-owner helper changes are needed first: `tools: support SAFE-owned PDP upgrades`
- [ ] Share the Mainnet implementation address, verification links, calldata, and rollout notes for independent review
- [ ] Stage the Mainnet SAFE transaction
- [ ] Collect SAFE signer approvals
- [ ] Confirm the Mainnet execution date/time
- [ ] Execute the Mainnet SAFE upgrade transaction
- [ ] Verify the Mainnet proxy implementation slot
- [ ] Verify the Mainnet proxy is on `vX.Y.Z`
- [ ] Publish completion/update communication

### Release Closeout

- [ ] Tag the deployed commit as `vX.Y.Z`
- [ ] Update `CHANGELOG.md` release date and deployed addresses
- [ ] Finalize release notes on `main`
  - Suggested PR title: `docs(changelog): finalize vX.Y.Z release notes`
- [ ] Sync PDPVerifier source, ABI, and deployments in `filecoin-services`
- [ ] Create follow-up issue in `fwss-subgraph`
- [ ] Close this rollout issue
  - If the runbook or issue template need improvement afterward: `docs: add PDPVerifier upgrade checklist`

## Deployment / Verification Details

Fill these in as comments or update them here once known.

- Runbook revision/blob URL:
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

1. Runbook reference, deploy commit, and Calibration constructor values
2. Calibration implementation deployment output
3. Calibration verification links and SAFE transaction review request
4. Calibration execution transaction link and smoke-test results
5. Mainnet implementation deployment output
6. Mainnet verification links and SAFE transaction review request
7. Scheduled Mainnet execution window
8. Mainnet execution transaction link and post-upgrade verification
9. Release-closeout links (`CHANGELOG`, tag, `filecoin-services`, `fwss-subgraph`)
