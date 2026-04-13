# Makefile for PDP Contracts

# Variables
RPC_URL ?=
KEYSTORE ?=
PASSWORD ?=

# Generated files
LAYOUT=src/PDPVerifierLayout.sol
LAYOUT_JSON=src/PDPVerifierLayout.json

# Default target
.PHONY: default
default: build test

# All target including installation
.PHONY: all
all: install build test

# Install dependencies
.PHONY: install
install:
	forge install

# Build target
.PHONY: build
build:
	forge build --via-ir

# Test target
.PHONY: test
test:
	forge test --via-ir -vv

# Deployment targets
.PHONY: deploy-calibnet
deploy-calibnet:
	./tools/deploy-calibnet.sh

.PHONY: deploy-devnet
deploy-devnet:
	./tools/deploy-devnet.sh

.PHONY: deploy-mainnet
deploy-mainnet:
	./tools/deploy-mainnet.sh

# Extract just the ABI arrays into abi/ContractName.abi.json
.PHONY: extract-abis
extract-abis:
	mkdir -p abi
	@find out -type f -name '*.json' | while read file; do \
	  name=$$(basename "$${file%.*}"); \
	  jq '.abi' "$${file}" > "abi/$${name}.abi.json"; \
	done

# Contract size check
.PHONY: contract-size-check
contract-size-check:
	@echo "Checking contract sizes..."
	bash tools/check-contract-size.sh

# Storage layout generation
$(LAYOUT): tools/generate_storage_layout.sh src/PDPVerifier.sol
	bash tools/generate_storage_layout.sh src/PDPVerifier.sol:PDPVerifier | forge fmt -r - > $@

# Storage layout JSON (full metadata for upgrade safety checks)
$(LAYOUT_JSON): src/PDPVerifier.sol
	forge inspect --json src/PDPVerifier.sol:PDPVerifier storageLayout | jq '[.storage[] | {label, slot, offset, type}]' > $@

# Main code generation target
.PHONY: gen
gen: check-tools $(LAYOUT) $(LAYOUT_JSON)
	@echo "Code generation complete"

# Force regeneration - useful when things are broken
.PHONY: force-gen
force-gen: clean-gen gen
	@echo "Force regeneration complete"

# Clean generated files only
.PHONY: clean-gen
clean-gen:
	@echo "Removing generated files..."
	@rm -f $(LAYOUT) $(LAYOUT_JSON)
	@echo "Generated files removed"

# Check required tools
.PHONY: check-tools
check-tools:
	@which jq >/dev/null 2>&1 || (echo "Error: jq is required but not installed" && exit 1)
	@which forge >/dev/null 2>&1 || (echo "Error: forge is required but not installed" && exit 1)

# Storage layout validation
.PHONY: check-layout
check-layout: force-gen
	@echo "Checking if layout files are up to date..."
	@git diff --exit-code $(LAYOUT) $(LAYOUT_JSON) || (echo "Error: Layout files are stale. Please commit the generated changes." && exit 1)
	@echo "Checking storage layout for destructive changes..."
	@bash tools/check_storage_layout.sh