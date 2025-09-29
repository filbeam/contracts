## Specification

### FilBeam (Operator) Contract

#### Overview

The Filecoin Beam (FilBeam) contract is responsible for managing CDN (cache-hit) and cache-miss data set egress usage data reported by the off-chain rollup worker and settlement of payment rails. Payment rails are managed by the Filecoin Warm Storage Service (FWSS) contract. The FilBeam contract interacts with the FWSS contract to facilitate fund transfers based on reported usage data with rate-based billing.

#### Constructor
**Method**: `constructor(address fwssAddress, uint256 _cdnRatePerByte, uint256 _cacheMissRatePerByte)`

**Parameters**:
- `address fwssAddress`: Address of the FWSS contract
- `uint256 _cdnRatePerByte`: Rate per byte for CDN usage billing (must be > 0)
- `uint256 _cacheMissRatePerByte`: Rate per byte for cache-miss usage billing (must be > 0)

**Validations**:
- FWSS address cannot be zero address
- Both rates must be greater than zero
- Sets deployer as contract owner

#### Data Structure
**DataSetUsage Struct**:
- `uint256 cdnBytesUsed`: Accumulated CDN bytes used between settlements
- `uint256 cacheMissBytesUsed`: Accumulated cache-miss bytes used between settlements
- `uint256 maxReportedEpoch`: Highest epoch number reported for this dataset
- `uint256 lastCDNSettlementEpoch`: Last epoch settled for CDN payment rail
- `uint256 lastCacheMissSettlementEpoch`: Last epoch settled for cache-miss payment rail
- `bool isInitialized`: Flag indicating if dataset has been initialized

#### Usage Reporting
**Method**: `reportUsageRollup(uint256 dataSetId, uint256 newEpoch, int256 cdnBytesUsed, int256 cacheMissBytesUsed)`

- **Access**: Contract owner only
- **Purpose**: Accepts periodic usage reports from the rollup worker
- **Epoch Requirements**:
  - Epoch must be > 0
  - Epoch must be greater than previously reported epochs for the dataset
  - Each epoch can only be reported once per dataset
- **Usage Requirements**:
  - Both usage amounts must be non-negative
  - Usage accumulates in the dataset between settlements
- **State Updates**:
  - Initialize dataset on first report
  - Accumulate usage data
  - Update max reported epoch
  - Mark epoch as reported
- **Events**: Emits `UsageReported` event

**Method**: `reportUsageRollupBatch(uint256[] dataSetIds, uint256[] epochs, int256[] cdnBytesUsed, int256[] cacheMissBytesUsed)`

- **Access**: Contract owner only
- **Purpose**: Accepts multiple usage reports in a single transaction for improved gas efficiency
- **Parameter Requirements**:
  - All arrays must have equal length
  - Each array element follows same validation rules as single method
- **Batch Processing**:
  - Processes all reports atomically (all succeed or all fail)
  - Maintains same epoch ordering and validation rules per dataset
  - Prevents duplicate epoch reporting within the batch
- **Gas Efficiency**: Significantly reduces transaction costs for bulk reporting operations
- **Events**: Emits individual `UsageReported` event for each processed report
- **Use Case**: Ideal for rollup workers reporting multiple usage periods

#### Payment Rail Settlement

**Method**: `settleCDNPaymentRail(uint256 dataSetId)`

- **Access**: Publicly callable (anyone can trigger settlement)
- **Calculation Period**: From last CDN settlement epoch + 1 to max reported epoch
- **Settlement Logic**:
  - Calculate settlement amount: `cdnBytesUsed * cdnRatePerByte`
  - Call FWSS contract to execute fund transfer for CDN rail only
  - Reset accumulated CDN usage to zero
- **State Updates**: Update last CDN settlement epoch to max reported epoch
- **Requirements**: Dataset must be initialized and have unreported usage
- **Events**: Emits `CDNSettlement` event
- **Independent Operation**: Can be called independently of cache-miss settlement

**Method**: `settleCacheMissPaymentRail(uint256 dataSetId)`

- **Access**: Publicly callable (typically called by Storage Providers)
- **Calculation Period**: From last cache-miss settlement epoch + 1 to max reported epoch
- **Settlement Logic**:
  - Calculate settlement amount: `cacheMissBytesUsed * cacheMissRatePerByte`
  - Call FWSS contract to execute fund transfer for cache-miss rail only
  - Reset accumulated cache-miss usage to zero
- **State Updates**: Update last cache-miss settlement epoch to max reported epoch
- **Requirements**: Dataset must be initialized and have unreported usage
- **Events**: Emits `CacheMissSettlement` event
- **Independent Operation**: Can be called independently of CDN settlement

#### Payment Rail Termination
**Method**: `terminateCDNPaymentRails(uint256 dataSetId)`

- **Access**: Contract owner only
- **Requirements**: Dataset must be initialized
- **Process**: Forward termination call to FWSS contract
- **Events**: Emits `PaymentRailsTerminated` event

#### Data Access
**Method**: `getDataSetUsage(uint256 dataSetId)`

**Returns**:
- `uint256 cdnBytesUsed`: Current accumulated CDN usage
- `uint256 cacheMissBytesUsed`: Current accumulated cache-miss usage
- `uint256 maxReportedEpoch`: Highest reported epoch
- `uint256 lastCDNSettlementEpoch`: Last CDN settlement epoch
- `uint256 lastCacheMissSettlementEpoch`: Last cache-miss settlement epoch
- `bool isInitialized`: Dataset initialization status

#### Ownership Management
**Method**: `transferOwnership(address newOwner)`

- **Access**: Contract owner only
- **Requirements**: New owner cannot be zero address
- **Purpose**: Transfer contract ownership

#### Events
- `UsageReported(uint256 indexed dataSetId, uint256 indexed epoch, int256 cdnBytesUsed, int256 cacheMissBytesUsed)`
- `CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount)`
- `CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount)`
- `PaymentRailsTerminated(uint256 indexed dataSetId)`

#### Error Conditions
- `OnlyOwner()`: Caller is not the contract owner
- `InvalidEpoch()`: Invalid epoch number or ordering
- `EpochAlreadyReported()`: Attempt to report same epoch twice
- `NoUsageToSettle()`: No unreported usage available for settlement
- `InvalidUsageAmount()`: Invalid usage amount (negative values or zero address)
- `DataSetNotInitialized()`: Dataset has not been initialized
- `InvalidRate()`: Invalid rate configuration (zero rates)

### Filecoin Warm Storage Service (FWSS) Contract Interface

**Method**: `settleCDNPaymentRails(uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount)`
- **Purpose**: Settle CDN or cache-miss payment rails based on calculated amounts
- **Access**: Callable only by FilBeam contract
- **Parameters**: Either cdnAmount or cacheMissAmount will be zero depending on settlement type

**Method**: `terminateCDNPaymentRails(uint256 dataSetId)`
- **Purpose**: Terminate CDN payment rails for a specific dataset
- **Access**: Callable only by FilBeam contract

### Key Implementation Features

#### Rate-Based Billing
- Configurable rates per byte for both CDN and cache-miss usage
- Settlement amounts calculated as: `usage * rate`
- Rates set at contract deployment and immutable

#### Independent Settlement Rails
- CDN and cache-miss settlements operate independently
- Each rail tracks its own settlement epoch
- Allows flexible settlement patterns for different stakeholders

#### Usage Accumulation
- Usage data accumulates between settlements
- Only unsettled usage is stored in contract state
- Settlement resets accumulated usage for that rail

#### Epoch Management
- Strict epoch ordering enforcement
- Prevents duplicate epoch reporting
- Supports batched reporting of multiple epochs via `reportUsageRollupBatch` method for gas efficiency
- Independent epoch tracking per dataset