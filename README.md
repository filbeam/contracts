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

The FilBeamOperator contract requires the following constructor parameters:

```solidity
constructor(
    address fwssAddress,           // FWSS contract address
    uint256 _cdnRatePerByte,       // Rate per byte for CDN usage
    uint256 _cacheMissRatePerByte, // Rate per byte for cache-miss usage
    address _filBeamController      // Address authorized to report usage
)
```

#### Deployment Example

Deploy the contract using Forge script:

```bash
PRIVATE_KEY=<deployer_private_key> \
FILBEAM_CONTROLLER=<filbeam_controller_address> \
FWSS_ADDRESS=<fwss_contract_address> \
USDFC_ADDRESS=<usdc_contract_address> \
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
function recordUsageRollupBatch(
    uint256[] calldata dataSetIds,
    uint256[] calldata epochs,
    uint256[] calldata cdnBytesUsed,
    uint256[] calldata cacheMissBytesUsed
) external onlyFilBeamOperatorController
```

### Settlement Operations

```solidity
function settleCDNPaymentRailBatch(uint256[] calldata dataSetIds) external
function settleCacheMissPaymentRailBatch(uint256[] calldata dataSetIds) external
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
function setFilBeamOperatorController(address _filBeamController) external onlyOwner
```

**Rate Management**
```solidity
function setCDNRatePerByte(uint256 _cdnRatePerByte) external onlyOwner
function setCacheMissRatePerByte(uint256 _cacheMissRatePerByte) external onlyOwner
```

### View Functions

**Dataset Information**
```solidity
function getDataSetUsage(uint256 dataSetId) external view returns (
    uint256 cdnBytesUsed,
    uint256 cacheMissBytesUsed,
    uint256 maxReportedEpoch,
    uint256 lastCDNSettlementEpoch,
    uint256 lastCacheMissSettlementEpoch
)
```

## Key Concepts

### Batch Operations
- **Gas Efficient**: Reduce transaction costs for bulk operations
- **Atomic**: All operations in a batch succeed or all fail
- **Independent Rails**: CDN and cache-miss settlements operate independently

### Pricing Model
- **Usage-Based**: Calculated as `usage_bytes * rate_per_byte`
- **Configurable Rates**: Owner can update rates via `setCDNRatePerByte` and `setCacheMissRatePerByte`
- **Direct Settlement**: Rates are applied directly during settlement calculations

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
