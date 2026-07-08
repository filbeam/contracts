#!/bin/bash

# SP Settlement Tool for FilBeam
# Settles outstanding cache-miss amounts for SP-provided dataset IDs.

set -e

# Configuration
RPC_URL="${RPC_URL:-http://localhost:8545}"
PRIVATE_KEY="${PRIVATE_KEY}"
FILBEAM_OPERATOR_ADDRESS="${FILBEAM_OPERATOR_ADDRESS}"
DATASET_IDS="${DATASET_IDS}"
BATCH_SIZE="${BATCH_SIZE:-50}"

# Check required variables
if [ -z "$PRIVATE_KEY" ] || [ -z "$FILBEAM_OPERATOR_ADDRESS" ] || [ -z "$DATASET_IDS" ]; then
    echo "Error: Missing required environment variables."
    echo "Required: PRIVATE_KEY, FILBEAM_OPERATOR_ADDRESS, DATASET_IDS"
    echo "Optional: RPC_URL (default: localhost), BATCH_SIZE (default: 50)"
    echo ""
    echo "Example:"
    echo "  export DATASET_IDS=\"11291,11300,11305\""
    echo "  export FILBEAM_OPERATOR_ADDRESS=\"0x...\""
    echo "  export PRIVATE_KEY=\"0x...\""
    echo "  ./tools/settle-cache-miss-egress.sh"
    exit 1
fi

echo "--- FilBeam SP Settlement Tool ---"
echo "RPC URL: $RPC_URL"
echo "Operator: $FILBEAM_OPERATOR_ADDRESS"
echo "Dataset IDs: $DATASET_IDS"
echo "----------------------------------"

# 1. Parse dataset IDs from comma-separated input
IFS=',' read -ra INPUT_IDS <<< "$DATASET_IDS"
echo "Received ${#INPUT_IDS[@]} dataset IDs."

# 2. Check each dataset for unsettled cache-miss usage
echo ""
echo "Checking usage amounts..."
SETTLE_LIST=()

for dataset_id in "${INPUT_IDS[@]}"; do
    # Trim whitespace
    dataset_id=$(echo "$dataset_id" | tr -d '[:space:]')

    # Call dataSetUsage(uint256) -> (uint256 cacheMissAmount, uint256 maxReportedEpoch)
    USAGE_RAW=$(cast call "$FILBEAM_OPERATOR_ADDRESS" "dataSetUsage(uint256)(uint256,uint256)" "$dataset_id" --rpc-url "$RPC_URL" 2>&1) || {
        echo "  Dataset $dataset_id: failed to query usage, skipping."
        continue
    }

    # Parse cacheMissAmount (1st line)
    CACHE_MISS_AMOUNT=$(echo "$USAGE_RAW" | sed -n '1p' | awk '{print $1}')

    if [ ! -z "$CACHE_MISS_AMOUNT" ] && [ "$CACHE_MISS_AMOUNT" -gt 0 ] 2>/dev/null; then
        echo "  Dataset $dataset_id: unsettled cache-miss amount = $CACHE_MISS_AMOUNT"
        SETTLE_LIST+=("$dataset_id")
    else
        echo "  Dataset $dataset_id: no outstanding amount."
    fi
done

if [ ${#SETTLE_LIST[@]} -eq 0 ]; then
    echo ""
    echo "No datasets with outstanding cache-miss settlement needed."
    exit 0
fi

echo ""
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
    echo "  Dataset IDs: $BATCH_STR"
    echo "  Submitting transaction..."
    
    TX_OUTPUT=$(cast send "$FILBEAM_OPERATOR_ADDRESS" 'settleCacheMissPaymentRails(uint256[])' "$BATCH_STR" \
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
            echo "  Settlement successful!"
        else
            echo "  Transaction failed!"
        fi
    else
        echo "  Failed to submit transaction:"
        echo "  $TX_OUTPUT"
    fi
    echo ""
done

echo "=== Settlement Summary ==="
echo "Total datasets processed: $TOTAL"
echo "Batches submitted: $BATCH_NUM"
echo "Settlement process completed."
