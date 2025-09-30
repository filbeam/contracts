# FilBeam Contract

FilBeam is a smart contract for managing CDN and cache-miss usage-based payments in the Filecoin ecosystem. It provides batch processing capabilities and flexible decimal pricing support.

## Features

- **Usage Reporting**: Single and batch methods for reporting CDN and cache-miss usage
- **Rail Settlements**: Independent settlement for CDN and cache-miss payment rails
- **Access Control**: Separate roles for contract management and usage reporting

## Built with Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Documentation: https://book.getfoundry.sh/

## Usage

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

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy FilBeam Contract

The FilBeam contract can be deployed using the provided deployment script with flexible pricing configuration.

#### Environment Variables

Set the following environment variables before deployment:

```bash
export PRIVATE_KEY="0x1234..."                    # Deployer's private key (deployer becomes contract owner)
export FWSS_ADDRESS="0xabc..."                    # FWSS contract address
export USDFC_ADDRESS="0xdef..."                   # USDFC token contract address
export CDN_PRICE_USD_PER_TIB="1250"              # CDN price (scaled by PRICE_DECIMALS)
export CACHE_MISS_PRICE_USD_PER_TIB="1575"       # Cache miss price (scaled by PRICE_DECIMALS)
export PRICE_DECIMALS="2"                        # Number of decimal places (2 = cents precision)
export FILBEAM_CONTROLLER="0x789..."             # (Optional) Address authorized to report usage (defaults to deployer)
```

#### Deployment Examples

**Example 1: Decimal Pricing ($12.50 CDN, $15.75 Cache Miss) with Custom Controller**
```bash
PRIVATE_KEY=0x1234... \
FWSS_ADDRESS=0xabc... \
USDFC_ADDRESS=0xdef... \
CDN_PRICE_USD_PER_TIB=1250 \
CACHE_MISS_PRICE_USD_PER_TIB=1575 \
PRICE_DECIMALS=2 \
FILBEAM_CONTROLLER=0x789... \
forge script script/DeployFilBeam.s.sol:DeployFilBeam --rpc-url <your_rpc_url> --broadcast
```

**Example 2: Whole Dollar Pricing ($10 CDN, $15 Cache Miss) - Controller Defaults to Deployer**
```bash
PRIVATE_KEY=0x1234... \
FWSS_ADDRESS=0xabc... \
USDFC_ADDRESS=0xdef... \
CDN_PRICE_USD_PER_TIB=10 \
CACHE_MISS_PRICE_USD_PER_TIB=15 \
PRICE_DECIMALS=0 \
forge script script/DeployFilBeam.s.sol:DeployFilBeam --rpc-url <your_rpc_url> --broadcast
```

**Example 3: High Precision Pricing ($9.995 CDN, $12.750 Cache Miss)**
```bash
PRIVATE_KEY=0x1234... \
FWSS_ADDRESS=0xabc... \
USDFC_ADDRESS=0xdef... \
CDN_PRICE_USD_PER_TIB=9995 \
CACHE_MISS_PRICE_USD_PER_TIB=12750 \
PRICE_DECIMALS=3 \
FILBEAM_CONTROLLER=0x789... \
forge script script/DeployFilBeam.s.sol:DeployFilBeam --rpc-url <your_rpc_url> --broadcast
```

#### Pricing Configuration Guide

| Desired Price | CDN_PRICE_USD_PER_TIB | PRICE_DECIMALS | Result |
|---------------|----------------------|----------------|---------|
| $10.00/TiB    | 10                   | 0              | $10.00  |
| $12.50/TiB    | 1250                 | 2              | $12.50  |
| $9.99/TiB     | 999                  | 2              | $9.99   |
| $15.750/TiB   | 15750                | 3              | $15.750 |
| $7.5/TiB      | 75                   | 1              | $7.5    |

#### Deployment Output

The deployment script provides detailed information about the deployed contract:

```
=== FilBeam Deployment Complete ===
FilBeam deployed at: 0x123...

=== Configuration ===
FWSS Address: 0xabc...
USDFC Address: 0xdef...
USDFC Decimals: 6
Price Decimals: 2
Owner: 0x789...
FilBeam Controller: 0x789...

=== Pricing ===
CDN Price (scaled input): 1250
CDN Rate (USDFC per byte): 11368
Cache Miss Price (scaled input): 1575
Cache Miss Rate (USDFC per byte): 14324

=== Actual USD Prices ===
CDN: scaled 1250 with 2 decimals
Cache Miss: scaled 1575 with 2 decimals
```

## Contract API

### Usage Reporting

**Single Report**
```solidity
function reportUsageRollup(
    uint256 dataSetId,
    uint256 newEpoch,
    uint256 cdnBytesUsed,
    uint256 cacheMissBytesUsed
) external onlyFilBeamController
```

**Batch Reports**
```solidity
function reportUsageRollupBatch(
    uint256[] calldata dataSetIds,
    uint256[] calldata epochs,
    uint256[] calldata cdnBytesUsed,
    uint256[] calldata cacheMissBytesUsed
) external onlyFilBeamController
```

### Settlement Operations

**Single Settlement**
```solidity
function settleCDNPaymentRail(uint256 dataSetId) external
function settleCacheMissPaymentRail(uint256 dataSetId) external
```

**Batch Settlement**
```solidity
function settleCDNPaymentRailBatch(uint256[] calldata dataSetIds) external
function settleCacheMissPaymentRailBatch(uint256[] calldata dataSetIds) external
```

### Data Set Management

**Payment Rail Termination**
```solidity
function terminateCDNPaymentRails(uint256 dataSetId) external onlyFilBeamController
```

### Contract Management

**Ownership & Controller**
```solidity
function transferOwnership(address newOwner) external onlyOwner
function setFilBeamController(address _filBeamController) external onlyOwner
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
- **Rate-Based**: Usage calculated as `bytes * rate_per_byte`
- **Decimal Support**: Flexible pricing with configurable decimal precision
- **Token Agnostic**: Works with any ERC20 token (USDFC assumed)

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
