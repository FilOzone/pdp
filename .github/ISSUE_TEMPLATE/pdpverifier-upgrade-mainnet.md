---
name: PDPVerifier Upgrade - Mainnet
about: Track a PDPVerifier proxy upgrade on Mainnet
title: "Mainnet: PDPVerifier upgrade from `vA.B.C` to `vX.Y.Z`"
labels: ""
assignees: ""
---

## Summary

Track the Mainnet rollout of `PDPVerifier` from `vA.B.C` to `vX.Y.Z`.

This issue is the operational checklist for the production rollout and release closeout.

Detailed command reference:
- [`docs/pdpverifier-upgrade-checklist.md`](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md)

Draft / final release notes:
- [`CHANGELOG.md`](https://github.com/FilOzone/pdp/blob/main/CHANGELOG.md)

## Notes

- This issue is for Mainnet only.
- Link the completed Calibration issue here before execution.
- Record major steps as issue comments as you go.
- If the live proxy predates `announcePlannedUpgrade()`, use the legacy one-step flow and `tools/upgrade.sh`.
- Do not deploy until all bytecode-affecting PRs are merged to `main`.

## Preconditions

- [ ] Calibration upgrade issue completed successfully: #
- [ ] Final deploy commit on `main` confirmed
- [ ] Final release version confirmed in `src/PDPVerifier.sol`
  - If a version-only fix PR is needed: `chore: correctly set version to vX.Y.Z`

## Checklist

### Release Input

Command reference:
- [Freeze the deploy commit](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#freeze-deploy-commit)
- [Confirm constructor values](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#confirm-constructor-values)
- [Confirm live proxy owner and version](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#confirm-live-proxy-owner-and-version)

- [ ] Confirm the exact git commit on `main` to deploy
- [ ] Confirm the intended `VERSION` in `src/PDPVerifier.sol`
- [ ] Confirm Mainnet constructor values
  - [ ] `initializerVersion`
  - [ ] `USDFC_TOKEN_ADDRESS`
  - [ ] `USDFC_SYBIL_FEE`
  - [ ] `PAYMENTS_CONTRACT_ADDRESS`
- [ ] Read the current Mainnet proxy initializer counter
- [ ] Confirm the current Mainnet proxy owner
- [ ] Confirm the current Mainnet proxy version

### Implementation Publish

Command reference:
- [Mainnet deploy](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#mainnet-deploy-implementation)
- [Mainnet sanity-check implementation](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#mainnet-sanity-check-implementation)
- [Mainnet verify implementation](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#mainnet-verify-implementation)

- [ ] Deploy the new `PDPVerifier` implementation to Mainnet
  - If deploy tooling needs to be updated first: `tools: update PDPVerifier deploy scripts for 4-arg constructor`
- [ ] Verify the implementation on Sourcify
- [ ] Verify the implementation on Blockscout
- [ ] Verify the implementation on Filfox (optional)
- [ ] Sanity-check `VERSION()` and immutable values on the implementation

### Upgrade Prep

Command reference:
- [Mainnet SAFE payload](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#mainnet-generate-safe-payload)
- [Independent review and signer approval](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#mainnet-independent-review)

- [ ] Draft and send initial upgrade communication
  - If release notes need to be drafted or refreshed first: `docs(changelog): draft vX.Y.Z release notes`
- [ ] Generate the SAFE upgrade transaction payload
  - If SAFE/contract-owner helper changes are needed first: `tools: support SAFE-owned PDP upgrades`
- [ ] Share the implementation address, verification links, calldata, and rollout notes for independent review
- [ ] Stage the SAFE transaction
- [ ] Collect SAFE signer approvals
- [ ] Confirm the execution date/time

### Execution

Command reference:
- [Mainnet execute upgrade](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#mainnet-execute-upgrade)

- [ ] Execute the SAFE upgrade transaction
- [ ] Verify the proxy implementation slot
- [ ] Verify the proxy is on `vX.Y.Z`
- [ ] Publish completion/update communication

### Release Closeout

Command reference:
- [Tag the deployed commit](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#tag-deployed-commit)
- [Finalize changelog](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#finalize-changelog)
- [Sync filecoin-services](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#sync-filecoin-services)
- [fwss-subgraph follow-up](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#fwss-subgraph-follow-up)

- [ ] Tag the deployed commit as `vX.Y.Z`
- [ ] Update `CHANGELOG.md` release date and deployed addresses
- [ ] Finalize release notes on `main`
  - Suggested PR title: `docs(changelog): finalize vX.Y.Z release notes`
- [ ] Sync PDPVerifier source, ABI, and deployments in `filecoin-services`
- [ ] Create follow-up issue in `fwss-subgraph`
- [ ] Close the Mainnet rollout issue
  - If the runbook or issue templates need improvement afterward: `docs: add PDPVerifier upgrade checklist`

## Deployment / Verification Details

Fill these in as comments or update them here once known.

- Calibration dependency issue:
- Deploy commit:
- Release tag:
- Mainnet proxy address:
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

1. Deploy commit and constructor values
2. Implementation deployment output
3. Verification links
4. SAFE transaction link / independent review request
5. Scheduled execution window
6. Execution transaction link
7. Post-upgrade verification results
8. Release-closeout links (`CHANGELOG`, tag, `filecoin-services`, `fwss-subgraph`)
