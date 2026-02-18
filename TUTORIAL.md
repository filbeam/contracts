# Tutorial: SP Settlement Tool

This guide explains how Service Providers (SPs) can use the `settle-sp.sh` tool to settle outstanding cache-miss usage amounts for their datasets.

## Prerequisites

1. **Foundry**: The tool uses `cast` from the Foundry toolkit.
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```
2. **jq**: JSON processor used for parsing transaction output.
   ```bash
   # macOS
   brew install jq
   # Ubuntu/Debian
   sudo apt-get install jq
   ```

## Setup

Export the following variables in your terminal:

```bash
export RPC_URL="https://your-rpc-url"
export PRIVATE_KEY="0xyour_private_key"
export OPERATOR_ADDRESS="0x..."        # FilBeamOperator contract address
export DATASET_IDS="11291,11300,11305"  # Your dataset IDs (comma-separated)
```

## Running the Tool

1. **Make the script executable** (if not already):
   ```bash
   chmod +x tools/settle-sp.sh
   ```

2. **Run the script**:
   ```bash
   ./tools/settle-sp.sh
   ```

### What the tool does:
1. **Checks**: Queries the `FilBeamOperator` contract for each dataset to see if there are unsettled cache-miss amounts (`cacheMissAmount > 0`).
2. **Settles**: Submits batch transactions (max 50 datasets per tx) to settle the outstanding amounts.

## Batching and Limits

The script default batch size is **50**. This is designed to stay within Filecoin gas limits.
If you have many datasets, the script will submit multiple transactions sequentially.

To change the batch size:
```bash
export BATCH_SIZE=25
./tools/settle-sp.sh
```

## Troubleshooting

- **No outstanding amounts**: All datasets are already settled. Nothing to do.
- **Failed to query usage**: The dataset ID may not exist on the `FilBeamOperator` contract. Verify the ID is correct.
- **Gas issues**: If transactions fail due to out-of-gas, try reducing the `BATCH_SIZE`.
- **Permission denied**: Ensure you are running with a private key that has sufficient funds for gas. Anyone can trigger settlement, but the gas cost is borne by the caller.
