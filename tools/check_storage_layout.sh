#!/usr/bin/env bash
# Check that storage layout changes are additive only.
# Prevents destructive changes to upgradeable contract storage:
# - Removing existing storage slots
# - Changing the slot number of an existing variable
# - Inserting new slots in the middle (shifting existing slots)
# Allowed: Appending new slots at the end (highest slot numbers)
#
# Usage: check_storage_layout.sh [<base_layout.sol> <new_layout.sol>]
#   No args: compares HEAD to working tree
#   Two args: compares base_layout.sol to new_layout.sol

set -euo pipefail

# Clean up temp files on exit
TEMP_FILES=()
cleanup() { rm -f "${TEMP_FILES[@]:-}" 2>/dev/null || true; }
trap cleanup EXIT

# Extract slot definitions from layout file (format: "NAME NUMBER" per line)
extract_slots() {
    local file="$1"
    grep -E 'bytes32 constant [A-Z0-9_]+_SLOT = bytes32\(uint256\([0-9]+\)\);' "$file" 2>/dev/null | \
        sed -E 's/.*constant ([A-Z0-9_]+_SLOT).*uint256\(([0-9]+)\).*/\1 \2/' | \
        sort -k2 -n
}

# Function to validate a single layout file
validate_layout_format() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "Error: Layout file not found: $file" >&2
        return 1
    fi

    local slot_count=$(extract_slots "$file" | wc -l)
    if [ "$slot_count" -eq 0 ]; then
        echo "Error: No slot definitions found in: $file" >&2
        return 1
    fi

    # Check for gaps or duplicate slot numbers
    local prev_num=-1
    local duplicate_count=0
    local gap_count=0

    while IFS=' ' read -r name num; do
        if [ "$num" -eq "$prev_num" ]; then
            echo "Error: Duplicate slot number $num for $name" >&2
            duplicate_count=$((duplicate_count + 1))
        elif [ "$num" -gt "$((prev_num + 1))" ]; then
            echo "Warning: Gap detected: slot $prev_num followed by $num" >&2
            gap_count=$((gap_count + 1))
        fi
        prev_num="$num"
    done < <(extract_slots "$file")

    if [ "$duplicate_count" -gt 0 ]; then
        return 1
    fi

    return 0
}

# Function to compare two layouts and detect destructive changes
compare_layouts() {
    local base_file="$1"
    local new_file="$2"

    # Extract slots
    local base_slots_file=$(mktemp)
    local new_slots_file=$(mktemp)
    TEMP_FILES+=("$base_slots_file" "$new_slots_file")

    extract_slots "$base_file" > "$base_slots_file"
    extract_slots "$new_file" > "$new_slots_file"

    # Find max slot number in base
    local max_base_slot=$(tail -1 "$base_slots_file" | awk '{print $2}')
    max_base_slot=${max_base_slot:-"-1"}

    local errors=0
    local warnings=0

    echo "Comparing storage layouts..."
    echo "  Base: $base_file (max slot: $max_base_slot)"
    echo "  New:  $new_file"

    # Check 1: No existing slots removed or modified
    while IFS=' ' read -r name num; do
        if ! grep -q "^${name} ${num}$" "$new_slots_file"; then
            if grep -q "^${name} " "$new_slots_file"; then
                local new_num=$(grep "^${name} " "$new_slots_file" | awk '{print $2}')
                echo "  Destructive: ${name} moved from slot ${num} to ${new_num}" >&2
            else
                echo "  Destructive: ${name} (slot ${num}) was removed" >&2
            fi
            errors=$((errors + 1))
        fi
    done < "$base_slots_file"

    # Check 2: New slots must be appended (slot numbers > max_base_slot)
    while IFS=' ' read -r name num; do
        if ! grep -q "^${name} " "$base_slots_file"; then
            if [ "$num" -le "$max_base_slot" ]; then
                echo "  Destructive: New slot ${name} inserted at ${num} (must be > ${max_base_slot})" >&2
                errors=$((errors + 1))
            else
                echo "  Added: ${name} at slot ${num}"
            fi
        fi
    done < "$new_slots_file"

    # Report results
    local base_count=$(wc -l < "$base_slots_file")
    local new_count=$(wc -l < "$new_slots_file")
    local added=$((new_count - base_count))

    echo ""
    if [ "$errors" -eq 0 ]; then
        echo "Storage layout check passed"
        echo "  Slots: ${base_count} → ${new_count} (+${added} added)"
        return 0
    else
        echo "Storage layout check failed (${errors} destructive change(s) detected)" >&2
        return 1
    fi
}

case $# in
    0)
        # No arguments: compare HEAD to working tree
        LAYOUT_FILE="src/PDPVerifierLayout.sol"

        if [ ! -f "$LAYOUT_FILE" ]; then
            echo "Error: Layout file not found: $LAYOUT_FILE" >&2
            exit 1
        fi

        # Get the base commit (HEAD for regular check, or base branch for PRs)
        if [ -n "${GITHUB_BASE_REF:-}" ]; then
            BASE_REF="origin/$GITHUB_BASE_REF"
        elif git rev-parse --quiet --verify HEAD~1 >/dev/null 2>&1; then
            BASE_REF="HEAD~1"
        else
            echo "Warning: No base commit found, assuming initial commit"
            BASE_REF=""
        fi

        if [ -z "$BASE_REF" ]; then
            # Initial commit - just validate format
            echo "Initial layout detected, validating format only..."
            if validate_layout_format "$LAYOUT_FILE"; then
                echo "Storage layout format validated"
                exit 0
            else
                exit 1
            fi
        fi

        # Get base version (must use repository-root relative path for git show)
        GIT_PREFIX=$(git rev-parse --show-prefix)
        FULL_LAYOUT_FILE="${GIT_PREFIX}${LAYOUT_FILE}"

        TEMP_BASE_LAYOUT=$(mktemp)
        TEMP_FILES+=("$TEMP_BASE_LAYOUT")

        if ! git show "$BASE_REF:$FULL_LAYOUT_FILE" > "$TEMP_BASE_LAYOUT" 2>/dev/null; then
            echo "Warning: Could not retrieve base layout, assuming new file"
            if validate_layout_format "$LAYOUT_FILE"; then
                echo "Storage layout format validated"
                exit 0
            else
                exit 1
            fi
        fi

        # Validate both layouts before comparison
        if ! validate_layout_format "$TEMP_BASE_LAYOUT"; then
            echo "Error: Base layout validation failed" >&2
            exit 1
        fi
        if ! validate_layout_format "$LAYOUT_FILE"; then
            echo "Error: New layout validation failed" >&2
            exit 1
        fi

        compare_layouts "$TEMP_BASE_LAYOUT" "$LAYOUT_FILE"
        ;;

    2)
        # Two arguments: compare base to new
        if ! validate_layout_format "$1"; then
            exit 1
        fi
        if ! validate_layout_format "$2"; then
            exit 1
        fi
        compare_layouts "$1" "$2"
        ;;

    *)
        echo "Usage: $0 [<base_layout.sol> <new_layout.sol>]" >&2
        echo ""
        echo "  With no args:  Compares HEAD to working tree" >&2
        echo "  With two args: Compares base_layout.sol to new_layout.sol" >&2
        exit 1
        ;;
esac