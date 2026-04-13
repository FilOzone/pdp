#!/usr/bin/env bash
# Check that storage layout changes are additive only.
# Prevents destructive changes to upgradeable contract storage:
# - Removing existing storage slots/variables
# - Changing the type of an existing variable
# - Changing the offset of an existing variable
# - Inserting new slots in the middle (shifting existing slots)
# Allowed: Appending new slots at the end (highest slot numbers)
#
# Usage: check_storage_layout.sh [<base_layout.json> <new_layout.json>]
#   No args: compares base branch/history to working tree
#   Two args: compares base_layout.json to new_layout.json

set -euo pipefail

# Clean up temp files on exit
TEMP_FILES=()
cleanup() { rm -f "${TEMP_FILES[@]:-}" 2>/dev/null || true; }
trap cleanup EXIT

LAYOUT_JSON="src/PDPVerifierLayout.json"

# Function to validate a single layout JSON file
validate_layout_json() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "Error: Layout file not found: $file" >&2
        return 1
    fi

    # Check if it's a valid JSON array
    if ! jq -e 'type == "array"' "$file" >/dev/null 2>&1; then
        echo "Error: Invalid JSON layout file (must be an array): $file" >&2
        return 1
    fi

    local entry_count=$(jq 'length' "$file")
    if [ "$entry_count" -eq 0 ]; then
        echo "Error: No storage entries found in: $file" >&2
        return 1
    fi

    # Check that all entries have required fields
    local missing=$(jq '[.[] | select(.label == null or .slot == null or .offset == null or .type == null)] | length' "$file")
    if [ "$missing" -gt 0 ]; then
        echo "Error: Some entries in $file are missing required fields (label, slot, offset, type)" >&2
        return 1
    fi

    # Check for duplicate slot+offset combinations
    local dupes=$(jq '[group_by(.slot + ":" + (.offset | tostring)) | .[] | select(length > 1)] | length' "$file")
    if [ "$dupes" -gt 0 ]; then
        echo "Error: Duplicate slot/offset combinations detected in $file" >&2
        return 1
    fi

    return 0
}

# Function to compare two layouts and detect destructive changes
compare_layouts() {
    local base_file="$1"
    local new_file="$2"
    local errors=0

    # Find the highest slot number currently in use in the base branch
    local max_base_slot=$(jq '[.[].slot | tonumber] | max // -1' "$base_file")

    local base_count=$(jq 'length' "$base_file")
    local new_count=$(jq 'length' "$new_file")

    echo "Comparing storage layouts..."
    echo "  Base: $base_file ($base_count entries, max slot: $max_base_slot)"
    echo "  New:  $new_file ($new_count entries)"

    # Check 1: No existing entries removed or modified (type/slot/offset)
    while IFS= read -r entry; do
        # Extract fields from the base entry
        local label=$(echo "$entry" | jq -r '.label')
        local slot=$(echo "$entry" | jq -r '.slot')
        local offset=$(echo "$entry" | jq -r '.offset')
        local type=$(echo "$entry" | jq -r '.type')

        # Try to find an entry with the exact same name (label) in the new file
        local new_entry=$(jq -c --arg l "$label" '.[] | select(.label == $l)' "$new_file")

        if [ -z "$new_entry" ]; then
            echo "  DESTRUCTIVE: Variable '$label' (slot $slot, offset $offset) was removed" >&2
            errors=$((errors + 1))
            continue
        fi

        # Extract fields from the new entry
        local new_slot=$(echo "$new_entry" | jq -r '.slot')
        local new_offset=$(echo "$new_entry" | jq -r '.offset')
        local new_type=$(echo "$new_entry" | jq -r '.type')

        # Compare fields
        if [ "$slot" != "$new_slot" ]; then
            echo "  DESTRUCTIVE: Variable '$label' slot changed from $slot to $new_slot" >&2
            errors=$((errors + 1))
        fi

        if [ "$offset" != "$new_offset" ]; then
            echo "  DESTRUCTIVE: Variable '$label' offset changed from $offset to $new_offset (slot $slot)" >&2
            errors=$((errors + 1))
        fi

        if [ "$type" != "$new_type" ]; then
            echo "  DESTRUCTIVE: Variable '$label' type changed from '$type' to '$new_type' (slot $slot)" >&2
            errors=$((errors + 1))
        fi
    done < <(jq -c '.[]' "$base_file")

    # Check 2: New entries must be appended (slot numbers > max_base_slot)
    while IFS= read -r entry; do
        local label=$(echo "$entry" | jq -r '.label')
        local slot=$(echo "$entry" | jq -r '.slot')
        local offset=$(echo "$entry" | jq -r '.offset')
        local type=$(echo "$entry" | jq -r '.type')

        # Check if this is a newly added variable
        local base_match=$(jq -c --arg l "$label" '.[] | select(.label == $l)' "$base_file")

        if [ -z "$base_match" ]; then
            if [ "$slot" -le "$max_base_slot" ]; then
                echo "  DESTRUCTIVE: New variable '$label' inserted at slot $slot (must be > $max_base_slot)" >&2
                errors=$((errors + 1))
            else
                echo "  Added: '$label' at slot $slot (offset $offset, type $type)"
            fi
        fi
    done < <(jq -c '.[]' "$new_file")

    # Report results
    local added=$((new_count - base_count))
    echo ""
    if [ "$errors" -eq 0 ]; then
        echo "Storage layout check passed"
        echo "  Entries: ${base_count} → ${new_count} (+${added} added)"
        return 0
    else
        echo "Storage layout check FAILED (${errors} destructive change(s) detected)" >&2
        return 1
    fi
}

case $# in
    0)
        # No arguments: compare base history to working tree JSON
        if [ ! -f "$LAYOUT_JSON" ]; then
            echo "Error: Layout API JSON not found locally: $LAYOUT_JSON" >&2
            exit 1
        fi

        IS_CI=${GITHUB_ACTIONS:-false}

        # Get the base commit (HEAD for regular check, or base branch for PRs)
        if [ -n "${GITHUB_BASE_REF:-}" ]; then
            BASE_REF="origin/$GITHUB_BASE_REF"
        elif git rev-parse --quiet --verify HEAD~1 >/dev/null 2>&1; then
            BASE_REF="HEAD~1"
        else
            if [ "$IS_CI" = "true" ]; then
                echo "Error: Running in CI but neither GITHUB_BASE_REF nor HEAD~1 could be resolved." >&2
                exit 1
            fi
            echo "Warning: No base commit found, assuming initial repository commit"
            BASE_REF=""
        fi

        if [ -z "$BASE_REF" ]; then
            # Genuine initial commit without base ref
            echo "Initial commit detected, validating format only..."
            if validate_layout_json "$LAYOUT_JSON"; then
                echo "Storage layout format validated"
                exit 0
            else
                exit 1
            fi
        fi

        # Ensure base ref actually exists in our git tree
        if ! git rev-parse --quiet --verify "$BASE_REF" >/dev/null 2>&1; then
            if [ "$IS_CI" = "true" ]; then
                echo "Error: CI base ref '$BASE_REF' could not be resolved! Please ensure fetch-depth: 0 is set in the workflow." >&2
                exit 1
            else
                echo "Error: Base ref '$BASE_REF' could not be resolved." >&2
                exit 1
            fi
        fi

        # Get base version (must use repository-root relative path for git show)
        GIT_PREFIX=$(git rev-parse --show-prefix)
        FULL_LAYOUT_JSON="${GIT_PREFIX}${LAYOUT_JSON}"

        # Check if the file ACTUALLY exists in the base branch tree
        if git cat-file -e "$BASE_REF:$FULL_LAYOUT_JSON" 2>/dev/null; then
            TEMP_BASE_LAYOUT=$(mktemp)
            TEMP_FILES+=("$TEMP_BASE_LAYOUT")

            if ! git show "$BASE_REF:$FULL_LAYOUT_JSON" > "$TEMP_BASE_LAYOUT" 2>/dev/null; then
                echo "Error: Layout file exists in base branch ($BASE_REF) but could not be retrieved via git show." >&2
                exit 1
            fi
        else
            # The file truly doesn't exist in the base ref
            echo "Initial layout detected (file does not exist in $BASE_REF), validating format only..."
            if validate_layout_json "$LAYOUT_JSON"; then
                echo "Storage layout format validated"
                exit 0
            else
                echo "Error: New layout validation failed" >&2
                exit 1
            fi
        fi

        # Validate both layouts before comparison
        if ! validate_layout_json "$TEMP_BASE_LAYOUT"; then
            echo "Error: Base layout validation failed on file $TEMP_BASE_LAYOUT" >&2
            exit 1
        fi
        if ! validate_layout_json "$LAYOUT_JSON"; then
            echo "Error: New layout validation failed" >&2
            exit 1
        fi

        compare_layouts "$TEMP_BASE_LAYOUT" "$LAYOUT_JSON"
        ;;

    2)
        # Two arguments: compare base JSON to new JSON explicitly
        if ! validate_layout_json "$1"; then exit 1; fi
        if ! validate_layout_json "$2"; then exit 1; fi
        compare_layouts "$1" "$2"
        ;;

    *)
        echo "Usage: $0 [<base_layout.json> <new_layout.json>]" >&2
        echo ""
        echo "  With no args:  Compares base branch to working tree" >&2
        echo "  With two args: Compares base_layout.json to new_layout.json" >&2
        exit 1
        ;;
esac