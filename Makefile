# Makefile for PDP Contracts

# Variables
RPC_URL ?=
KEYSTORE ?=
PASSWORD ?=
CHALLENGE_FINALITY ?=

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

.PHONY: deploy-mainnet
deploy-mainnet:
	./tools/deploy-mainnet.sh