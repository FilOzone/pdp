# Simple Version Release System

A minimal automated release system that watches for changes to the VERSION constant in PDPVerifier.sol.

## How It Works

### When You Update the Version

1. **Edit the VERSION constant** in [`src/PDPVerifier.sol`](https://github.com/FilOzone/pdp/blob/4214bd2e6ab997bb2d05208cd9f52c79e0d58cdf/src/PDPVerifier.sol#L158-L159):
   ```solidity
   string public constant VERSION = "2.1.0";  // Update this line
   ```

2. **Open a Pull Request** - The workflow automatically triggers

3. **Automatic Draft Release** - If the VERSION changed, the workflow:
   - ✅ Creates a git tag with the new version (e.g., `v2.1.0`)  
   - ✅ Creates a draft GitHub release
   - ✅ Auto-generates changelog from git commits since the last release
   - ✅ Adds a comment to your PR with the release link

### What Gets Created

The draft release includes:
- **Title**: `PDP v2.1.0`
- **Tag**: `v2.1.0` 
- **Changelog**: Auto-generated from git commits since the last release tag
- **Files Changed**: List of files modified since last release
- **Contract Info**: VERSION constant change details
- **Status**: Draft (ready for you to review and publish)

## Usage Examples

### Regular Release
```solidity
// Change this in src/PDPVerifier.sol
string public constant VERSION = "2.1.0";
```

### Pre-release  
```solidity
// The workflow automatically detects pre-releases
string public constant VERSION = "2.1.0-rc.1";
```

## Workflow File

- **`.github/workflows/version-release.yml`** - Single workflow that handles everything

## Manual Steps

1. **Update VERSION** in `PDPVerifier.sol`
2. **Write good commit messages** (they become your changelog):
   ```bash
   git commit -m "feat: add new data validation feature"
   git commit -m "fix: resolve memory leak in proof verification" 
   git commit -m "docs: update API documentation"
   ```
3. **Create PR** - automation handles the rest
4. **Review & Edit** the auto-generated changelog in the draft release
5. **Publish** when ready

## That's It! 

Simple, incremental, and focused on the core need: automatically creating draft releases when the contract version changes. 🚀
