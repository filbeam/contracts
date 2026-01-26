# FilBeamOperator Contract

FilBeamOperator is a smart contract used for aggregating CDN and cache-miss usage data and managing payment settlements for CDN payment rails operated by [Filecoin Warm Storage Service](https://github.com/FilOzone/filecoin-services).

## Features

- **Usage Reporting**: Batch methods for reporting CDN and cache-miss usage
- **Rail Settlements**: Independent settlement for CDN and cache-miss payment rails
- **Access Control**: Separate roles for contract management and usage reporting
- **Upgradeable**: Uses UUPS proxy pattern for safe contract upgrades

## Foundry

Documentation: https://book.getfoundry.sh/

## Prerequisites
- [Foundry](https://getfoundry.sh/) - Ethereum development toolchain

### Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Deploy FilBeamOperator Contract

For full deployment and migration guide refer to the [DEPLOYMENT](./DEPLOYMENT.md) document in this repository.

The FilBeamOperator contract uses the UUPS proxy pattern. Deployment creates:
1. **Implementation Contract** - Contains the logic (don't interact with this directly)
2. **Proxy Contract** - The address users interact with (stores all state)

The contract is initialized with the following parameters:

```solidity
function initialize(
    address filBeamOperatorController // Address authorized to report usage
)
```

#### Deployment Example

Deploy the contract using Forge script:

```bash
PRIVATE_KEY=<deployer_private_key> \
FILBEAM_CONTROLLER=<filbeam_controller_address> \
FWSS_ADDRESS=<fwss_contract_address> \
FWSS_STATE_VIEW_ADDRESS=<fwss_state_view_address> \
CDN_PRICE_USD_PER_TIB=<cdn_price_usd_per_tib> \
CACHE_MISS_PRICE_USD_PER_TIB=<cache_miss_price_usd_per_tib> \
PRICE_DECIMALS=<price_decimals> \
forge script script/DeployFilBeamOperator.s.sol \
--rpc-url <your_rpc_url> \
--broadcast
```

The deployment will output:
- **Proxy Address** - Use this address for all interactions
- **Implementation Address** - For reference only

**Note**: The deployer address automatically becomes the contract owner.

## Contract API

### Usage Reporting

```solidity
function recordUsageRollups(
    uint256 toEpoch,
    uint256[] calldata dataSetIds,
    uint256[] calldata cdnBytesUsed,
    uint256[] calldata cacheMissBytesUsed
) external onlyFilBeamOperatorController
```

### Settlement Operations

```solidity
function settleCDNPaymentRails(uint256[] calldata dataSetIds) external
function settleCacheMissPaymentRails(uint256[] calldata dataSetIds) external
```

### Data Set Management

**Payment Rail Termination**
```solidity
function terminateCDNPaymentRails(uint256 dataSetId) external onlyFilBeamOperatorController
```

### Contract Management

**Ownership & Controller**
```solidity
function transferOwnership(address newOwner) external onlyOwner
function setFilBeamOperatorController(address _filBeamOperatorController) external onlyOwner
```

**Upgrades (UUPS)**
```solidity
function upgradeToAndCall(address newImplementation, bytes memory data) external onlyOwner
function version() public pure returns (string memory)  // Returns current version
```

## Key Concepts

### Batch Operations
- **Gas Efficient**: Reduce transaction costs for bulk operations
- **Atomic**: All operations in a batch succeed or all fail
- **Independent Rails**: CDN and cache-miss settlements operate independently

### Pricing Model
- **Usage-Based**: Calculated as `usage_bytes * rate_per_byte` at report time
- **Immutable Rates**: Rates are set at deployment and cannot be changed, ensuring predictable pricing
- **Transparent Pricing**: All users can view the fixed rates on-chain
- **Partial Settlements**: Supports partial settlements when accumulated amount exceeds payment rail's `lockupFixed`

### Rail Settlement 
- **Independent Tracking**: CDN and cache-miss settlements tracked separately
- **Epoch-Based**: Settlement periods defined by epoch ranges
- **Accumulative**: Usage accumulates between settlements

### Upgradeability (UUPS Pattern)
- **Proxy Pattern**: Users interact with a proxy that delegates to an implementation
- **State Preservation**: All data is stored in the proxy and preserved during upgrades
- **Owner-Only Upgrades**: Only the contract owner can authorize upgrades
- **Version Tracking**: Use `version()` to verify the current implementation version

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
