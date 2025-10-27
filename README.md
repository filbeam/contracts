# FilBeamOperator Contract

FilBeamOperator is a smart contract used for aggregating CDN and cache-miss usage data and managing payment settlements for CDN payment rails operated by [Filecoin Warm Storage Service](https://github.com/FilOzone/filecoin-services).

## Features

- **Usage Reporting**: Batch methods for reporting CDN and cache-miss usage
- **Rail Settlements**: Independent settlement for CDN and cache-miss payment rails
- **Access Control**: Separate roles for contract management and usage reporting

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

The FilBeamOperator contract requires the following constructor parameters:

```solidity
constructor(
    address fwssAddress,           // FWSS contract address
    address _paymentsAddress,      // Payments contract address for rail management
    uint256 _cdnRatePerByte,       // Rate per byte for CDN usage
    uint256 _cacheMissRatePerByte, // Rate per byte for cache-miss usage
    address _filBeamOperatorController      // Address authorized to report usage
)
```

#### Deployment Example

Deploy the contract using Forge script:

```bash
PRIVATE_KEY=<deployer_private_key> \
FILBEAM_CONTROLLER=<filbeam_controller_address> \
FWSS_ADDRESS=<fwss_contract_address> \
CDN_PRICE_USD_PER_TIB=<cdn_price_usd_per_tib> \
CACHE_MISS_PRICE_USD_PER_TIB=<cache_miss_price_usd_per_tib> \
PRICE_DECIMALS=<price_decimals> \
forge script script/DeployFilBeamOperator.s.sol \
--rpc-url <your_rpc_url> \
--broadcast
```

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
