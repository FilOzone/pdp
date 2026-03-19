---
name: PDPVerifier Upgrade - Calibnet
about: Track a PDPVerifier proxy upgrade on Calibration
title: "Calibnet: PDPVerifier upgrade from `vA.B.C` to `vX.Y.Z`"
labels: ""
assignees: ""
---

## Summary

Track the Calibration rollout of `PDPVerifier` from `vA.B.C` to `vX.Y.Z`.

This issue is the operational checklist for the Calibration upgrade rehearsal. Mainnet should be tracked in a separate issue.

Detailed command reference:
- [`docs/pdpverifier-upgrade-checklist.md`](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md)

Draft / final release notes:
- [`CHANGELOG.md`](https://github.com/FilOzone/pdp/blob/main/CHANGELOG.md)

## Notes

- This issue is for Calibration only.
- Record major steps as issue comments as you go, rather than editing all details into the top post.
- If the live proxy predates `announcePlannedUpgrade()`, use the legacy one-step flow and `tools/upgrade.sh`.
- Do not deploy until all bytecode-affecting PRs are merged to `main`.

## Checklist

### Release Input

Command reference:
- [Freeze the deploy commit](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#freeze-deploy-commit)
- [Confirm constructor values](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#confirm-constructor-values)
- [Confirm live proxy owner and version](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#confirm-live-proxy-owner-and-version)

- [ ] Confirm the exact git commit on `main` to deploy
- [ ] Confirm the intended `VERSION` in `src/PDPVerifier.sol`
  - If a version-only fix PR is needed: `chore: correctly set version to vX.Y.Z`
- [ ] Confirm Calibration constructor values
  - [ ] `initializerVersion`
  - [ ] `USDFC_TOKEN_ADDRESS`
  - [ ] `USDFC_SYBIL_FEE`
  - [ ] `PAYMENTS_CONTRACT_ADDRESS`
- [ ] Read the current Calibration proxy initializer counter
- [ ] Confirm the current Calibration proxy owner
- [ ] Confirm the current Calibration proxy version

### Implementation Publish

Command reference:
- [Calibration deploy](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#calibration-deploy-implementation)
- [Calibration sanity-check implementation](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#calibration-sanity-check-implementation)
- [Calibration verify implementation](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#calibration-verify-implementation)

- [ ] Deploy the new `PDPVerifier` implementation to Calibration
  - If deploy tooling needs to be updated first: `tools: update PDPVerifier deploy scripts for 4-arg constructor`
- [ ] Verify the implementation on Sourcify
- [ ] Verify the implementation on Blockscout
- [ ] Verify the implementation on Filfox (optional)
- [ ] Sanity-check `VERSION()` and immutable values on the implementation

### Upgrade Prep

Command reference:
- [Calibration SAFE payload](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#calibration-generate-safe-payload)
- [Independent review](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#calibration-independent-review)

- [ ] Generate the SAFE upgrade transaction payload
  - If SAFE/contract-owner helper changes are needed first: `tools: support SAFE-owned PDP upgrades`
- [ ] Share the implementation address, verification links, and calldata for independent review
- [ ] Stage the SAFE transaction
- [ ] Confirm the execution window

### Execution

Command reference:
- [Calibration execute upgrade](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#calibration-execute-upgrade)
- [Calibration smoke tests](https://github.com/FilOzone/pdp/blob/main/docs/pdpverifier-upgrade-checklist.md#calibration-smoke-tests)

- [ ] Execute the SAFE upgrade transaction
- [ ] Verify the proxy implementation slot
- [ ] Verify the proxy is on `vX.Y.Z`
- [ ] Run lightweight read-only smoke tests
- [ ] Post Calibration completion/update communication
  - If release notes need to be drafted or refreshed first: `docs(changelog): draft vX.Y.Z release notes`

### Exit Criteria

- [ ] Calibration proxy upgraded successfully
- [ ] Smoke tests pass
- [ ] No blocker remains for Mainnet rollout
  - If this rollout changed the expected process, consider a docs follow-up: `docs: add PDPVerifier upgrade checklist`

## Deployment / Verification Details

Fill these in as comments or update them here once known.

- Deploy commit:
- Release tag target:
- Calibration proxy address:
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

## Suggested Comment Cadence

Recommended issue comments to post as the rollout progresses:

1. Deploy commit and constructor values
2. Implementation deployment output
3. Verification links
4. SAFE transaction link / calldata review request
5. Execution transaction link
6. Post-upgrade verification and smoke-test results
