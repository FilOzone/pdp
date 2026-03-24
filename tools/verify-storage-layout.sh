#!/usr/bin/env bash
set -euo pipefail

# This script verifies that the checked-in storage layout matches the freshly generated one
# and ensures that only additions are made to the storage layout when compared to the base branch.

CONTRACT="PDPVerifier"
LAYOUT_FILE="src/${CONTRACT}ServiceLayout.sol"
TMP_LAYOUT_FILE="src/${CONTRACT}ServiceLayout.sol.tmp"

echo "Verifying storage layout for ${CONTRACT}..."

GEN_SCRIPT="tools/gen-storage-layout.sh"
if [ ! -f "$GEN_SCRIPT" ]; then
    echo "Error: Gen script not found at $GEN_SCRIPT"
    exit 1
fi

# Run gen script which outputs to the actual LAYOUT_FILE, 
# but we first move the original aside so we can compare it!
if [ -f "$LAYOUT_FILE" ]; then
    cp "$LAYOUT_FILE" "${LAYOUT_FILE}.bak"
else
    # If the file didn't exist at all locally, just create an empty backup
    touch "${LAYOUT_FILE}.bak"
fi

# Generate fresh layout
bash "$GEN_SCRIPT"
mv "$LAYOUT_FILE" "$TMP_LAYOUT_FILE"

# Restore original file for comparison
if [ -s "${LAYOUT_FILE}.bak" ]; then
    mv "${LAYOUT_FILE}.bak" "$LAYOUT_FILE"
else
    rm "${LAYOUT_FILE}.bak"
    touch "$LAYOUT_FILE"
fi

# 1. Check if files match
# (Compare locally checked-in layout vs what make gen produces)
if [ ! -s "$LAYOUT_FILE" ]; then
    echo "Error: Checked-in storage layout does not exist. Please run 'make gen' and commit."
    rm -f "$TMP_LAYOUT_FILE" 
    exit 1
fi

if ! diff -q "$LAYOUT_FILE" "$TMP_LAYOUT_FILE" > /dev/null; then
    echo "Error: Checked-in storage layout does not match freshly generated one!"
    echo "Please run 'make gen' and commit the changes."
    diff -u "$LAYOUT_FILE" "$TMP_LAYOUT_FILE" || true
    rm "$TMP_LAYOUT_FILE"
    exit 1
fi

# 2. Check for destructive changes (only additions allowed vs base branch)
BASE_BRANCH=${GITHUB_BASE_REF:-main}
BASE_LAYOUT_FILE="src/${CONTRACT}ServiceLayout.sol.base"

echo "Checking for destructive storage changes against branch: $BASE_BRANCH..."
if git show "origin/$BASE_BRANCH:$LAYOUT_FILE" > "$BASE_LAYOUT_FILE" 2>/dev/null || git show "$BASE_BRANCH:$LAYOUT_FILE" > "$BASE_LAYOUT_FILE" 2>/dev/null; then
    OLD_SLOTS=$(grep "\[slot:" "$BASE_LAYOUT_FILE" | sed 's/^[[:space:]]*//')
    NEW_SLOTS=$(grep "\[slot:" "$TMP_LAYOUT_FILE" | sed 's/^[[:space:]]*//')

    while IFS= read -r old_line; do
        if [ -z "$old_line" ]; then continue; fi
        if ! echo "$NEW_SLOTS" | grep -Fqx "$old_line"; then
            echo "Error: Destructive storage change detected!"
            echo "Missing or modified slot from base branch ($BASE_BRANCH):"
            echo "  $old_line"
            rm "$BASE_LAYOUT_FILE"
            rm "$TMP_LAYOUT_FILE"
            exit 1
        fi
    done <<< "$OLD_SLOTS"
    rm "$BASE_LAYOUT_FILE"
else
    echo "Base layout not found on $BASE_BRANCH. Skipping destructive change check."
fi

echo "Storage layout verification passed."
rm "$TMP_LAYOUT_FILE"
