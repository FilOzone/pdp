# Makefile for PDP Contracts

# Variables
RPC_URL ?=
KEYSTORE ?=
PASSWORD ?=
CHALLENGE_FINALITY ?=

# Contract verification variables
# All these variables must be provided when running the verify target
# Example: make verify CONTRACT_NAME=PDPVerifier CONTRACT_FILE=src/PDPVerifier.sol CONTRACT_ADDRESS=0x... NETWORK=calibration
CONTRACT_NAME =
CONTRACT_FILE =
CONTRACT_ADDRESS =
NETWORK =
COMPILER_VERSION ?= v0.8.23+commit.f704f362
OPTIMIZE ?= --optimize

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
	npm install

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

.PHONY: verify
verify:
	@if [ -z "$(CONTRACT_NAME)" ]; then \
		echo "Error: CONTRACT_NAME is required"; \
		echo "Usage: make verify CONTRACT_NAME=<name> CONTRACT_FILE=<file> CONTRACT_ADDRESS=<address> NETWORK=<network> [COMPILER_VERSION=<version>] [OPTIMIZE=<flag>]"; \
		exit 1; \
	fi
	@if [ -z "$(CONTRACT_FILE)" ]; then \
		echo "Error: CONTRACT_FILE is required"; \
		echo "Usage: make verify CONTRACT_NAME=<name> CONTRACT_FILE=<file> CONTRACT_ADDRESS=<address> NETWORK=<network> [COMPILER_VERSION=<version>] [OPTIMIZE=<flag>]"; \
		exit 1; \
	fi
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS is required"; \
		echo "Usage: make verify CONTRACT_NAME=<name> CONTRACT_FILE=<file> CONTRACT_ADDRESS=<address> NETWORK=<network> [COMPILER_VERSION=<version>] [OPTIMIZE=<flag>]"; \
		exit 1; \
	fi
	@if [ -z "$(NETWORK)" ]; then \
		echo "Error: NETWORK is required"; \
		echo "Usage: make verify CONTRACT_NAME=<name> CONTRACT_FILE=<file> CONTRACT_ADDRESS=<address> NETWORK=<network> [COMPILER_VERSION=<version>] [OPTIMIZE=<flag>]"; \
		exit 1; \
	fi
	./tools/verify-contract.sh \
		--compiler $(COMPILER_VERSION) \
		$(OPTIMIZE) \
		--node-modules ./node_modules \
		--contract-name $(CONTRACT_NAME) \
		$(CONTRACT_FILE) \
		$(CONTRACT_ADDRESS) \
		$(NETWORK)

.PHONY: deploy-mainnet
deploy-mainnet:
	./tools/deploy-mainnet.sh

