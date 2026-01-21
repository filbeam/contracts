# FilBeamOperator Deployment & Migration Guide

## Table of Contents
1. [Overview](#overview)
2. [Initial Deployment](#initial-deployment)
3. [Migration from FWSS to FilBeamOperator](#migration-from-fwss-to-filbeamoperator)
4. [Future Contract Upgrades](#future-contract-upgrades)
5. [Rollback Procedures](#rollback-procedures)

## Overview

The FilBeamOperator contract manages CDN and cache-miss usage reporting and payment settlement for the FilBeam service. The contract uses the **UUPS proxy pattern** for upgradeability.

### Architecture
- **Proxy Contract**: The address users interact with (stores all state)
- **Implementation Contract**: Contains the business logic (can be upgraded)

This guide covers deployment, upgrades, and migration procedures.

## Initial Deployment

### Prerequisites

1. **Deployed Contracts**:
   - FilecoinWarmStorageService contract (with `transferFilBeamController` capability)
   - Payments contract (Filecoin Pay)

2. **Environment Setup**:
   ```bash
   # Required environment variables
   export PRIVATE_KEY="0x..."                    # Deployer's private key
   export FILBEAM_CONTROLLER="0x..."             # FilBeamOperator controller address
   export FWSS_ADDRESS="0x..."                   # FilecoinWarmStorageService Proxy contract address
   export FWSS_STATE_VIEW_ADDRESS="0x..."        # FilecoinWarmStorageServiceStateViewcontract contract address
   export CDN_PRICE_USD_PER_TIB=700              # $7.00/TiB (with 2 decimals)
   export CACHE_MISS_PRICE_USD_PER_TIB=850       # $8.50/TiB (with 2 decimals)
   export PRICE_DECIMALS=2                       # Price decimal precision
   ```

**NOTE:**

- Rates are immutable once deployed
- Calculate carefully based on business requirements
- Consider token decimals (USDFC typically has 18 decimals)

### Deployment Steps

#### Step 1: Deploy FilBeamOperator (Proxy + Implementation)

```bash
# Deploy the contract
forge script script/DeployFilBeamOperator.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify

# Expected output:
# === FilBeamOperator Deployment Complete ===
# === Contract Addresses ===
# Proxy Address (use this!): 0x...      <-- This is the address you use
# Implementation Address: 0x...          <-- For reference only
# === Verification ===
# Contract Version: 1.0.0
# ...
```

#### Step 2: Verify Deployment

```bash
# Set the PROXY address (not implementation!)
export FILBEAM_OPERATOR_PROXY_ADDRESS=0x...

# Verify contract configuration
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "fwssContractAddress()" --rpc-url $RPC_URL
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "paymentsContractAddress()" --rpc-url $RPC_URL
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "cdnRatePerByte()" --rpc-url $RPC_URL
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "cacheMissRatePerByte()" --rpc-url $RPC_URL
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "filBeamOperatorController()" --rpc-url $RPC_URL
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "version()" --rpc-url $RPC_URL  # Should return "1.0.0"
```

#### Step 3: Transfer FWSS Controller Authorization

```bash
# Current FWSS controller should execute this
cast send $FWSS_ADDRESS \
  "transferFilBeamController(address)" \
  $FILBEAM_OPERATOR_PROXY_ADDRESS \
  --private-key $CURRENT_CONTROLLER_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

#### Step 4: Verify Authorization Transfer

```bash
# Verify FilBeamOperator can call FWSS methods
# This should not revert
cast call $FWSS_ADDRESS \
  "getDataSetInfo(uint256)" \
  1 \
  --from $FILBEAM_OPERATOR_PROXY_ADDRESS \
  --rpc-url $RPC_URL
```

## Migration from FWSS to FilBeamOperator

### Migration Steps

#### Step 1: Deploy New FilBeamOperator Contract
- Deploy FilBeamOperator contract as described in the Initial Deployment section
- Transfer FWSS controller authorization to FilBeamOperator

#### Step 2: Update Off-Chain Components
- Update the FilBeam controller address (`FILBEAM_CONTROLLER_PRIVATE_KEY` secret)
- Update all worker configurations to point to FilBeamOperator contract address (`FILBEAM_CONTRACT_ADDRESS` environment variable)

#### Step 3: Verify Operations
- Monitor initial usage reporting batches
- Check for `UsageReported` events on-chain
- Verify `CDNSettlement` and `CacheMissSettlement` events
- Monitor `PaymentRailsTerminated` events for terminated datasets

## Future Contract Upgrades

FilBeamOperator supports two types of upgrades:

1. **UUPS Upgrade** - For bug fixes or feature additions (preserves rates and state)
2. **Rate Change Migration** - Requires deploying a new proxy (rates are immutable per deployment)

### UUPS Upgrade (Bug Fixes / Features)

Use this for logic changes that don't require modifying rates.

#### Step 1: Deploy New Implementation

```bash
# Deploy only the new implementation contract
forge create src/FilBeamOperator.sol:FilBeamOperator \
  --rpc-url $RPC_URL \
  --private-key $OWNER_PRIVATE_KEY

export FILBEAM_OPERATOR_IMPL_ADDRESS=0x...  # New implementation address
```

#### Step 2: Upgrade the Proxy

```bash
# Owner calls upgradeToAndCall on the proxy
cast send $FILBEAM_OPERATOR_PROXY_ADDRESS \
  "upgradeToAndCall(address,bytes)" \
  $NEW_IMPLEMENTATION \
  "0x" \
  --private-key $OWNER_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

#### Step 3: Verify Upgrade

```bash
# Check new version
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "version()" --rpc-url $RPC_URL
# Should return new version (e.g., "1.1.0")

# Verify state is preserved
cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "cdnRatePerByte()" --rpc-url $RPC_URL
```

### Rate Change Migration

Since rates are immutable in FilBeamOperator, changing rates requires deploying a new proxy. FWSS can only have one authorized FilBeamController at a time, which affects settlement capabilities.

### Migration Approach: Clean Transition

#### Step 1: Deploy New Contract

```bash
# Deploy new contract with updated rates
export CDN_PRICE_USD_PER_TIB=1500            # New rate: $15.00/TiB
export CACHE_MISS_PRICE_USD_PER_TIB=1800     # New rate: $18.00/TiB

forge script script/DeployFilBeamOperator.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify

export FILBEAM_OPERATOR_V2_ADDRESS=0x...
```

#### Step 2: Prepare for Migration
- Stop usage reporting to v1 contract (by stopping `usage-reporter` worker)
- Ensure all accumulated usage in v1 is settled
- Monitor v1 contract for zero accumulated balances

#### Step 3: Transfer FWSS Controller

```bash
# Execute from v1 owner wallet
cast send $FILBEAM_OPERATOR_V1_ADDRESS \
  "transferFwssFilBeamController(address)" \
  $FILBEAM_OPERATOR_V2_ADDRESS \
  --private-key $OWNER_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

#### Step 4: Activate v2 Operations
- Update all worker configurations to use v2 contract address
- Resume usage reporting with v2 contract (by starting `usage-reporter` worker)
- Enable settlement operations on v2
- Verify all operations are functioning correctly

#### Step 5: Decommission v1
- Remove all references to v1 contract from configurations
- Archive v1 deployment information for historical reference

### Alternative: Data Migration

If accumulated usage cannot be settled naturally, consider implementing a migration utility in v2 contract which would allow us to migrate the usage amounts calculated under the different rate:

```solidity
// Add to FilBeamOperator v2
function migrateDataSetUsage(
    uint256[] calldata dataSetIds,
    uint256[] calldata cdnAmounts,
    uint256[] calldata cacheMissAmounts,
    uint256[] calldata maxReportedEpochs
) external onlyOwner {
    // Import usage data from v1
}
```

This allows direct migration of accumulated usage amounts before transferring the FWSS controller.

## Rollback Procedures

### Emergency Rollback

If critical issues are discovered after migration:

#### Step 1: Pause Operations
- Stop all off-chain operations immediately
- Prevent any new transactions to the problematic contract

#### Step 2: Transfer Controller Back

```bash
# If FWSS controller was transferred
cast send $FILBEAM_OPERATOR_PROXY_ADDRESS \
  "transferFwssFilBeamController(address)" \
  $PREVIOUS_CONTROLLER_ADDRESS \
  --private-key $OWNER_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

#### Step 3: Restore Previous Configuration
- Revert all configuration changes to point to previous contract
- Resume operations with the previous stable contract

#### Step 4: Data Recovery
- Identify any gaps in usage reporting
- Query logs for missing usage data
- Manually report missing epochs if necessary
- Verify data consistency after recovery
