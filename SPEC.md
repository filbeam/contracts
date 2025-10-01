## Specification

### FilBeam (Operator) Contract

#### Overview

The Filecoin Beam (FilBeam) contract is responsible for managing CDN (cache-hit) and cache-miss data set egress usage data reported by the off-chain rollup worker and settlement of payment rails. Payment rails are managed by the Filecoin Warm Storage Service (FWSS) contract. The FilBeam contract interacts with the FWSS contract to facilitate fund transfers based on reported usage data with rate-based billing.

#### Initialization
**Method**: `constructor(address fwssAddress, uint256 _cdnRatePerByte, uint256 _cacheMissRatePerByte, address _filBeamController)`

**Parameters**:
- `address fwssAddress`: Address of the FWSS contract
- `uint256 _cdnRatePerByte`: Rate per byte for CDN usage billing (must be > 0)
- `uint256 _cacheMissRatePerByte`: Rate per byte for cache-miss usage billing (must be > 0)
- `address _filBeamController`: Address authorized to report usage and terminate payment rails

**Owner**:
- The deployer (msg.sender) automatically becomes the contract owner

**Validations**:
- FWSS address cannot be zero address
- Both rates must be greater than zero
- FilBeam controller cannot be zero address

#### Data Structure
**DataSetUsage Struct**:
- `uint256 cdnBytesUsed`: Accumulated CDN bytes used between settlements
- `uint256 cacheMissBytesUsed`: Accumulated cache-miss bytes used between settlements
- `uint256 maxReportedEpoch`: Highest epoch number reported for this dataset (0 indicates uninitialized dataset)
- `uint256 lastCDNSettlementEpoch`: Last epoch settled for CDN payment rail
- `uint256 lastCacheMissSettlementEpoch`: Last epoch settled for cache-miss payment rail

#### Usage Reporting
**Method**: `reportUsageRollup(uint256 dataSetId, uint256 newEpoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed)`

- **Access**: FilBeam controller only
- **Purpose**: Accepts periodic usage reports from the rollup worker
- **Epoch Requirements**:
  - Epoch must be > 0
  - Epoch must be greater than previously reported epochs for the dataset
  - Each epoch can only be reported once per dataset
- **Usage Requirements**:
  - Usage accumulates in the dataset between settlements
- **State Updates**:
  - Initialize dataset on first report (sets maxReportedEpoch to non-zero value)
  - Accumulate usage data
  - Update max reported epoch
- **Events**: Emits `UsageReported` event with uint256 values

**Method**: `reportUsageRollupBatch(uint256[] dataSetIds, uint256[] epochs, uint256[] cdnBytesUsed, uint256[] cacheMissBytesUsed)`

- **Access**: FilBeam controller only
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
  - Only calls FWSS contract if calculated amount > 0 (gas optimization)
  - Reset accumulated CDN usage to zero
- **State Updates**: Update last CDN settlement epoch to max reported epoch
- **Requirements**: Dataset must be initialized and have unreported usage
- **Events**: Emits `CDNSettlement` event
- **Independent Operation**: Can be called independently of cache-miss settlement

**Method**: `settleCDNPaymentRailBatch(uint256[] dataSetIds)`

- **Access**: Publicly callable (anyone can trigger settlement)
- **Purpose**: Settles CDN payment rails for multiple datasets in a single transaction
- **Batch Processing**:
  - Processes all settlements atomically (all succeed or all fail)
  - Each dataset follows same validation and settlement logic as single method
  - Maintains independent operation per dataset
- **Gas Efficiency**: Significantly reduces transaction costs for bulk settlement operations
- **Events**: Emits individual `CDNSettlement` event for each processed dataset
- **Use Case**: Ideal for batch settlement operations across multiple datasets

**Method**: `settleCacheMissPaymentRail(uint256 dataSetId)`

- **Access**: Publicly callable (typically called by Storage Providers)
- **Calculation Period**: From last cache-miss settlement epoch + 1 to max reported epoch
- **Settlement Logic**:
  - Calculate settlement amount: `cacheMissBytesUsed * cacheMissRatePerByte`
  - Only calls FWSS contract if calculated amount > 0 (gas optimization)
  - Reset accumulated cache-miss usage to zero
- **State Updates**: Update last cache-miss settlement epoch to max reported epoch
- **Requirements**: Dataset must be initialized and have unreported usage
- **Events**: Emits `CacheMissSettlement` event
- **Independent Operation**: Can be called independently of CDN settlement

**Method**: `settleCacheMissPaymentRailBatch(uint256[] dataSetIds)`

- **Access**: Publicly callable (typically called by Storage Providers)
- **Purpose**: Settles cache-miss payment rails for multiple datasets in a single transaction
- **Batch Processing**:
  - Processes all settlements atomically (all succeed or all fail)
  - Each dataset follows same validation and settlement logic as single method
  - Maintains independent operation per dataset
- **Gas Efficiency**: Significantly reduces transaction costs for bulk settlement operations
- **Events**: Emits individual `CacheMissSettlement` event for each processed dataset
- **Use Case**: Ideal for Storage Providers performing bulk settlement operations

#### Payment Rail Termination
**Method**: `terminateCDNPaymentRails(uint256 dataSetId)`

- **Access**: FilBeam controller only
- **Requirements**: Dataset must be initialized
- **Process**: Forward termination call to FWSS contract
- **Events**: Emits `PaymentRailsTerminated` event

#### Data Access
**Method**: `getDataSetUsage(uint256 dataSetId)`

**Returns**:
- `uint256 cdnBytesUsed`: Current accumulated CDN usage
- `uint256 cacheMissBytesUsed`: Current accumulated cache-miss usage
- `uint256 maxReportedEpoch`: Highest reported epoch (0 indicates uninitialized dataset)
- `uint256 lastCDNSettlementEpoch`: Last CDN settlement epoch
- `uint256 lastCacheMissSettlementEpoch`: Last cache-miss settlement epoch

#### Ownership Management
**Method**: `transferOwnership(address newOwner)`

- **Access**: Contract owner only
- **Requirements**: New owner cannot be zero address
- **Purpose**: Transfer contract ownership

#### FilBeam Controller Management
**Method**: `setFilBeamController(address _filBeamController)`

- **Access**: Contract owner only
- **Requirements**: FilBeam controller cannot be zero address
- **Purpose**: Update the authorized address for usage reporting and payment rail termination
- **Events**: Emits `FilBeamControllerUpdated` event

#### Rate Management
**Method**: `setCDNRatePerByte(uint256 _cdnRatePerByte)`

- **Access**: Contract owner only
- **Requirements**: Rate must be greater than zero
- **Purpose**: Update CDN rate per byte for future settlements
- **Events**: Emits `CDNRateUpdated` event

**Method**: `setCacheMissRatePerByte(uint256 _cacheMissRatePerByte)`

- **Access**: Contract owner only
- **Requirements**: Rate must be greater than zero
- **Purpose**: Update cache-miss rate per byte for future settlements
- **Events**: Emits `CacheMissRateUpdated` event

#### Events
- `UsageReported(uint256 indexed dataSetId, uint256 indexed epoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed)`
- `CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount)`
- `CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount)`
- `PaymentRailsTerminated(uint256 indexed dataSetId)`
- `FilBeamControllerUpdated(address indexed oldController, address indexed newController)`
- `CDNRateUpdated(uint256 oldRate, uint256 newRate)`
- `CacheMissRateUpdated(uint256 oldRate, uint256 newRate)`

#### Access Control
- **Owner**: Address authorized to manage contract ownership, set FilBeam controller, and update rates
- **FilBeam Controller**: Address authorized to report usage and terminate payment rails

#### Error Conditions
- `OwnableUnauthorizedAccount(address)`: Caller is not the contract owner
- `Unauthorized()`: Caller is not the FilBeam controller
- `InvalidEpoch()`: Invalid epoch number or ordering
- `NoUsageToSettle()`: No unreported usage available for settlement
- `InvalidUsageAmount()`: Invalid array lengths in batch operations
- `DataSetNotInitialized()`: Dataset has not been initialized
- `InvalidRate()`: Invalid rate configuration (zero rates)
- `InvalidAddress()`: Invalid address (zero address) provided

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
- Rates set at contract deployment and can be updated by owner via `setCDNRatePerByte` and `setCacheMissRatePerByte`

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