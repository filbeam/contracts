# Tutorial: SP Settlement Tool

This guide explains how Service Providers (SPs) can use the `settle-sp.sh` tool to automate the settlement of outstanding cache-miss usage amounts for their datasets.

## Prerequisites

1. **Foundry**: The tool uses `cast` from the Foundry toolkit.
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```
2. **jq**: JSON processor used for parsing blockchain logs.
   ```bash
   # macOS
   brew install jq
   # Ubuntu/Debian
   sudo apt-get install jq
   ```
3. **Environment Variables**: You will need to set several environment variables to run the script.

## Setup

Create a `.env` file or export the following variables in your terminal:

```bash
export RPC_URL="https://your-rpc-url"
export PRIVATE_KEY="0xyour_private_key"
export PROVIDER_ID=123                 # Your Service Provider ID
export FWSS_ADDRESS="0x..."            # FilecoinWarmStorageService address
export OPERATOR_ADDRESS="0x..."        # FilBeamOperator address
export FROM_BLOCK=5000000              # Optional: Block where FWSS was deployed
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
1. **Discovers**: Automatically finds all datasets created for your `PROVIDER_ID` by scanning the blockchain logs.
2. **Checks**: Queries the `FilBeamOperator` contract for each dataset to see if there are unsettled cache-miss amounts (`cacheMissAmount > 0`).
3. **Settles**: Submits batch transactions (max 50 datasets per tx) to settle the outstanding amounts.

## Batching and Limits

The script default batch size is **50**. This is designed to stay within Filecoin gas limits.
If you have thousands of datasets, the script will submit multiple transactions sequentially.

To change the batch size:
```bash
export BATCH_SIZE=50
./tools/settle-sp.sh
```

## Troubleshooting

- **No datasets found**: Ensure `PROVIDER_ID` and `FWSS_ADDRESS` are correct. If you know the block number when you registered, set `FROM_BLOCK` to speed up discovery.
- **Gas issues**: If transactions fail due to out-of-gas, try reducing the `BATCH_SIZE`.
- **Permission denied**: Ensure you are running with a private key that has sufficient funds for gas. Anyone can trigger settlement, but the gas cost is borne by the caller.
