# Makefile for PDP Contracts

# Variables
RPC_URL ?=
KEYSTORE_PATH ?=
PASSWORD ?=
CHALLENGE_FINALITY ?=

# Default target
.PHONY: all
all: build test

# Build target
.PHONY: build
build:
	forge build --via-ir

# Test target
.PHONY: test
test:
	forge test -vv

# Deployment targets
.PHONY: deploy-calibnet
deploy-calibnet:
	./tools/deploy-calibnet.sh

.PHONY: deploy-devnet
deploy-devnet:
	./tools/deploy-devnet.sh
