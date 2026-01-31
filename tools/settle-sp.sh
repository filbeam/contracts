#!/bin/bash

# SP Settlement Tool for FilBeam
# This script discovers datasets for a given provider ID and settles outstanding cache-miss amounts.

set -e

# Configuration
RPC_URL="${RPC_URL:-http://localhost:8545}"
PROVIDER_ID="${PROVIDER_ID}"
PRIVATE_KEY="${PRIVATE_KEY}"
OPERATOR_ADDRESS="${OPERATOR_ADDRESS}"
FWSS_ADDRESS="${FWSS_ADDRESS}"
FROM_BLOCK="${FROM_BLOCK:-0}"
BATCH_SIZE="${BATCH_SIZE:-100}"

# Check required variables
if [ -z "$PROVIDER_ID" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$OPERATOR_ADDRESS" ] || [ -z "$FWSS_ADDRESS" ]; then
    echo "Error: Missing required environment variables."
    echo "Required: PROVIDER_ID, PRIVATE_KEY, OPERATOR_ADDRESS, FWSS_ADDRESS"
    echo "Optional: RPC_URL (default: localhost), FROM_BLOCK (default: 0), BATCH_SIZE (default: 100)"
    exit 1
fi

echo "--- FilBeam SP Settlement Tool ---"
echo "RPC URL: $RPC_URL"
echo "Provider ID: $PROVIDER_ID"
echo "Operator: $OPERATOR_ADDRESS"
echo "FWSS: $FWSS_ADDRESS"
echo "----------------------------------"

# 1. Discover DataSets for the Provider
echo "Discovering datasets for provider $PROVIDER_ID..."
PROVIDER_HEX=$(printf '0x%064x' "$PROVIDER_ID")

# Event: DataSetCreated(uint256 indexed dataSetId, uint256 indexed providerId, ...)
# Topic 0 = keccak256(event signature), Topic 1 = dataSetId, Topic 2 = providerId
EVENT_SIG="DataSetCreated(uint256,uint256,uint256,uint256,uint256,address,address,address,string[],string[])"
EVENT_TOPIC=$(cast keccak "$EVENT_SIG")

# Fetch all logs from FWSS, then filter by event topic and providerId using jq
LOGS_JSON=$(cast logs \
    --rpc-url "$RPC_URL" \
    --address "$FWSS_ADDRESS" \
    --from-block "$FROM_BLOCK" \
    --json 2>/dev/null | jq '[.[] | select(.topics[0] == "'"$EVENT_TOPIC"'" and .topics[2] == "'"$PROVIDER_HEX"'")]')

if [ -z "$LOGS_JSON" ] || [ "$LOGS_JSON" == "[]" ]; then
    echo "No datasets found for this provider."
    exit 0
fi

# Extract and deduplicate DataSet IDs from logs (Topic 1 is dataSetId)
DATASET_IDS=$(echo "$LOGS_JSON" | jq -r '.[].topics[1]' | sort -u)

if [ -z "$DATASET_IDS" ]; then
    echo "Failed to parse dataset IDs from logs."
    exit 1
fi

COUNT=0
for id in $DATASET_IDS; do
    COUNT=$((COUNT + 1))
done
echo "Found $COUNT potential datasets."

# 2. Filter datasets with unsettled cache-miss usage
echo "Checking usage amounts..."
SETTLE_LIST=()

for id_hex in $DATASET_IDS; do
    # ID is in hex from logs, cast needs it
    dataset_id=$(cast --to-dec "$id_hex")
    
    # Call dataSetUsage(uint256) -> (uint256 cdnAmount, uint256 cacheMissAmount, uint256 maxReportedEpoch)
    # cacheMissAmount is the 2nd value
    USAGE_RAW=$(cast call "$OPERATOR_ADDRESS" "dataSetUsage(uint256)(uint256,uint256,uint256)" "$dataset_id" --rpc-url "$RPC_URL")
    
    # Parse 2nd value
    CACHE_MISS_AMOUNT=$(echo "$USAGE_RAW" | sed -n '2p' | tr -d '[:space:]')
    
    if [ ! -z "$CACHE_MISS_AMOUNT" ] && [ "$CACHE_MISS_AMOUNT" -gt 0 ]; then
        echo "Dataset $dataset_id has unsettled cache-miss amount: $CACHE_MISS_AMOUNT"
        SETTLE_LIST+=("$dataset_id")
    fi
done

if [ ${#SETTLE_LIST[@]} -eq 0 ]; then
    echo "No datasets found with outstanding cache-miss settlement needed."
    exit 0
fi

echo "Total datasets to settle: ${#SETTLE_LIST[@]}"

# 3. Batch settle
echo "Starting batch settlement (batch size: $BATCH_SIZE)..."
echo ""

TOTAL=${#SETTLE_LIST[@]}
BATCH_NUM=0
for ((i=0; i<TOTAL; i+=BATCH_SIZE)); do
    BATCH=("${SETTLE_LIST[@]:i:BATCH_SIZE}")
    BATCH_NUM=$((BATCH_NUM + 1))
    
    # Format batch as [id1,id2,...]
    BATCH_STR="["$(IFS=,; echo "${BATCH[*]}")"]"
    
    echo "=== Batch $BATCH_NUM of $(( (TOTAL + BATCH_SIZE - 1) / BATCH_SIZE )) ==="
    echo "Dataset IDs: $BATCH_STR"
    echo "Submitting transaction..."
    
    TX_OUTPUT=$(cast send "$OPERATOR_ADDRESS" 'settleCacheMissPaymentRails(uint256[])' "$BATCH_STR" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --json 2>&1)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo "$TX_OUTPUT" | jq -r '.transactionHash')
        TX_STATUS=$(echo "$TX_OUTPUT" | jq -r '.status')
        GAS_USED=$(echo "$TX_OUTPUT" | jq -r '.gasUsed')
        BLOCK_NUM=$(echo "$TX_OUTPUT" | jq -r '.blockNumber')
        
        echo "  Transaction Hash: $TX_HASH"
        echo "  Status: $TX_STATUS"
        echo "  Gas Used: $GAS_USED"
        echo "  Block Number: $BLOCK_NUM"
        
        if [ "$TX_STATUS" == "0x1" ] || [ "$TX_STATUS" == "1" ]; then
            echo "Settlement successful!"
        else
            echo "Transaction failed!"
        fi
    else
        echo "Failed to submit transaction:"
        echo "  $TX_OUTPUT"
    fi
    echo ""
done

echo "=== Settlement Summary ==="
echo "Total datasets processed: $TOTAL"
echo "Batches submitted: $BATCH_NUM"
echo "Settlement process completed."
