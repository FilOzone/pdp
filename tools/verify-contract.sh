#!/bin/bash

set -e

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

print_usage() {
    echo "Usage: $0 [options] <source_file> <contract_address> <network>"
    echo ""
    echo "Options:"
    echo "  --compiler <version>     Solidity compiler version (default: 0.8.20)"
    echo "  --optimize               Enable optimization"
    echo "  --runs <number>          Number of optimization runs (default: 200)"
    echo "  --license <type>         License type (default: UNLICENSED)"
    echo "  --contract-name <name>   Contract name (default: derived from source file)"
    echo "  --metadata <file>        Path to metadata.json file (optional)"
    echo "  --node-modules <path>    Path to node_modules directory (default: ./node_modules)"
    echo ""
    echo "Example:"
    echo "  $0 --compiler 0.8.20 --optimize --runs 200 src/PDPVerifier.sol 0x1234...5678 calibration"
}

copy_dependencies() {
    local source_file="$1"
    local target_dir="$2"
    local base_dir="$(dirname "$source_file")"
    local node_modules_path="${node_modules:-./node_modules}"
    local lib_path="./lib"

    local imports
    imports=$(grep -h '^import' "$source_file" | sed -n 's/.*['"'"'"]\(.*\)['"'"'"].*/\1/p')

    for imp in $imports; do
        local imp_path=""
        local target_imp_path="$imp"

        if [[ "$imp" == "@"* ]]; then
            if [ -f "$node_modules_path/$imp" ]; then
                imp_path="$node_modules_path/$imp"
            else
                local forge_imp="${imp#@}"
                forge_imp=$(echo "$forge_imp" | sed 's|/|/|')
                if [ -f "$lib_path/$forge_imp" ]; then
                    imp_path="$lib_path/$forge_imp"
                fi
            fi
        elif [[ "$imp" == ../* ]]; then
            imp_path="$(dirname "$base_dir")/${imp#../}"
        elif [[ "$imp" == /* ]]; then
            imp_path="./${imp}"
        else
            imp_path="$base_dir/$imp"
        fi

        if [ -f "$imp_path" ]; then
            local target_dir_path="$target_dir/$(dirname "$target_imp_path")"
            mkdir -p "$target_dir_path"
            
            cp "$imp_path" "$target_dir/$target_imp_path"
            echo "Copied dependency: $imp" >&2
            
            copy_dependencies "$imp_path" "$target_dir"
        else
            echo "Warning: Could not find dependency: $imp" >&2
        fi
    done
}

create_verification_payload() {
    local source_file="$1"
    local compiler="$2"
    local optimize="$3"
    local runs="$4"
    local license="$5"
    local contract_name="$6"
    local contract_address="$7"
    local metadata_file="$8"
    
    local payload_dir="$TEMP_DIR/payload"
    rm -rf "$payload_dir"
    mkdir -p "$payload_dir"
    
    local main_source_file=$(basename "${source_file%:*}")
    local main_contract_name="${contract_name:-${main_source_file%.sol}}"
    
    echo "Copying source files to payload directory..." >&2
    mkdir -p "$payload_dir/$(dirname "$source_file")"
    cp "$source_file" "$payload_dir/$source_file"
    copy_dependencies "$source_file" "$payload_dir"
    
    if [ -n "$metadata_file" ] && [ -f "$metadata_file" ]; then
        echo "Including metadata file: $metadata_file" >&2
        cp "$metadata_file" "$payload_dir/metadata.json"
    fi
    
    local input_json="$payload_dir/input.json"
    
    local sources_json="$TEMP_DIR/sources.json"
    echo "{}" > "$sources_json"
    
    local payload_files
    payload_files=$(cd "$payload_dir" && find . -type f -name '*.sol' -print)
    
    echo "$payload_files" | while IFS= read -r file; do
        if [ -n "$file" ]; then
            local rel_path="${file#./}"
            local content
            content=$(cat "$payload_dir/$rel_path" | jq -sR .)
            jq --arg path "$rel_path" --arg content "$content" \
               '. + {($path): {"content": $content}}' "$sources_json" > "$sources_json.tmp" && \
            mv "$sources_json.tmp" "$sources_json"
        fi
    done

    jq -n \
        --arg compiler "$compiler" \
        --argjson optimize "$optimize" \
        --arg runs "$runs" \
        --arg source_file "$main_source_file" \
        --arg contract_name "$main_contract_name" \
        --argjson sources "$(cat "$sources_json")" \
        '{
            language: "Solidity",
            sources: $sources,
            settings: {
                optimizer: {
                    enabled: $optimize,
                    runs: ($runs | tonumber)
                },
                evmVersion: "london",
                compilationTarget: {
                    ($source_file): ($contract_name)
                },
                libraries: {},
                metadata: {
                    bytecodeHash: "ipfs",
                    useLiteralContent: true
                },
                outputSelection: {
                    "*": {
                        "*": [
                            "abi",
                            "evm.bytecode",
                            "evm.deployedBytecode",
                            "evm.methodIdentifiers",
                            "metadata"
                        ],
                        "": ["ast"]
                    }
                }
            }
        }' > "$input_json"

    echo "$payload_dir"
}

submit_verification_request() {
    local payload_dir="$1"
    local contract_address="$2"
    local network="$3"
    
    local api_url="https://sourcify.dev/server/verify"
    
    local chain_id
    if [[ "$network" == "calibration" ]]; then
        chain_id="314159"
    elif [[ "$network" == "mainnet" ]]; then
        chain_id="314"
    else
        chain_id="$network"
    fi
    
    echo "Verifying contract on $network (chain ID: $chain_id)..." >&2
    
    echo "Files to be submitted:" >&2
    (cd "$payload_dir" && find . -type f -ls) >&2
    
    echo "Submitting verification request..." >&2
    
    local curl_cmd="curl -v -X POST"
    curl_cmd+=" -F \"address=$contract_address\""
    curl_cmd+=" -F \"chain=$chain_id\""
    
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            curl_cmd+=" -F \"files=@$file\""
        fi
    done < <(cd "$payload_dir" && find . -type f -print)
    
    curl_cmd+=" \"$api_url\""
    
    local response
    response=$(cd "$payload_dir" && eval "$curl_cmd")

    if echo "$response" | jq -e '.status == "success"' > /dev/null; then
        echo "Contract verification successful!" >&2
        echo "You can view the verified contract at: https://sourcify.dev/#/lookup/$chain_id/$contract_address" >&2
        return 0
    else
        echo "Contract verification failed!" >&2
        echo "Error: $(echo "$response" | jq -r '.message // "Unknown error"')" >&2
        echo "Full response: $response" >&2
        return 1
    fi
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --compiler)
            compiler="$2"
            shift 2
            ;;
        --optimize)
            optimize=true
            shift
            ;;
        --runs)
            runs="$2"
            shift 2
            ;;
        --license)
            license="$2"
            shift 2
            ;;
        --contract-name)
            contract_name="$2"
            shift 2
            ;;
        --metadata)
            metadata_file="$2"
            shift 2
            ;;
        --node-modules)
            node_modules="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

compiler="${compiler:-0.8.20}"
optimize="${optimize:-false}"
runs="${runs:-200}"
license="${license:-UNLICENSED}"
node_modules="${node_modules:-./node_modules}"

if [ $# -ne 3 ]; then
    echo "Error: Missing required arguments" >&2
    print_usage >&2
    exit 1
fi

source_file="$1"
contract_address="$2"
network="$3"

if [ ! -f "$source_file" ]; then
    echo "Error: Source file not found: $source_file" >&2
    exit 1
fi

if [ -n "$metadata_file" ] && [ ! -f "$metadata_file" ]; then
    echo "Error: Metadata file not found: $metadata_file" >&2
    exit 1
fi

echo "Creating verification payload..." >&2
payload_dir=$(create_verification_payload "$source_file" "$compiler" "$optimize" "$runs" "$license" "$contract_name" "$contract_address" "$metadata_file")

submit_verification_request "$payload_dir" "$contract_address" "$network"