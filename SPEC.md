## Specification

### FilBeamOperator (Operator) Contract

#### Overview

The Filecoin Beam (FilBeamOperator) contract is responsible for managing CDN (cache-hit) and cache-miss data set egress usage data reported by the off-chain rollup worker and settlement of payment rails. Payment rails are managed by the Filecoin Warm Storage Service (FWSS) contract. The FilBeamOperator contract interacts with the FWSS contract to facilitate fund transfers based on reported usage data with rate-based billing.

#### Initialization
**Method**: `constructor(address fwssAddress, uint256 _cdnRatePerByte, uint256 _cacheMissRatePerByte, address _filBeamOperatorController)`

**Parameters**:
- `address fwssAddress`: Address of the FWSS contract
- `uint256 _cdnRatePerByte`: Rate per byte for CDN usage billing (must be > 0)
- `uint256 _cacheMissRatePerByte`: Rate per byte for cache-miss usage billing (must be > 0)
- `address _filBeamOperatorController`: Address authorized to report usage and terminate payment rails

**Owner**:
- The deployer (msg.sender) automatically becomes the contract owner

**Validations**:
- FWSS address cannot be zero address
- Both rates must be greater than zero
- FilBeamOperator controller cannot be zero address

#### Data Structure
**DataSetUsage Struct**:
- `uint256 cdnAmount`: Accumulated CDN settlement amount between settlements (calculated at report time)
- `uint256 cacheMissAmount`: Accumulated cache-miss settlement amount between settlements (calculated at report time)
- `uint256 maxReportedEpoch`: Highest epoch number reported for this dataset (0 indicates uninitialized dataset)
- `uint256 lastCDNSettlementEpoch`: Last epoch settled for CDN payment rail
- `uint256 lastCacheMissSettlementEpoch`: Last epoch settled for cache-miss payment rail

#### Usage Reporting

**Method**: `recordUsageRollups(uint256[] dataSetIds, uint256[] epochs, uint256[] cdnBytesUsed, uint256[] cacheMissBytesUsed)`

- **Access**: FilBeamOperator controller only
- **Purpose**: Accepts multiple usage reports in a single transaction for improved gas efficiency
- **Epoch Requirements**:
  - Epoch must be > 0
  - Epoch must be greater than previously reported epochs for the dataset
  - Each epoch can only be reported once per dataset
- **Usage Requirements**:
  - Usage is converted to settlement amounts using current rates at report time
  - Amounts accumulate in the dataset between settlements
- **Parameter Requirements**:
  - All arrays must have equal length
- **Batch Processing**:
  - Processes all reports atomically (all succeed or all fail)
  - Maintains epoch ordering and validation rules per dataset
  - Prevents duplicate epoch reporting within the batch
- **State Updates**:
  - Initialize dataset on first report (sets maxReportedEpoch to non-zero value)
  - Calculate amounts: `cdnAmount = cdnBytesUsed * cdnRatePerByte`, `cacheMissAmount = cacheMissBytesUsed * cacheMissRatePerByte`
  - Accumulate calculated amounts
  - Update max reported epoch
- **Events**: Emits individual `UsageReported` event for each processed report (contains bytes, not amounts)

#### Payment Rail Settlement

**Method**: `settleCDNPaymentRails(uint256[] dataSetIds)`

- **Access**: Publicly callable (anyone can trigger settlement)
- **Purpose**: Settles CDN payment rails for multiple datasets in a single transaction
- **Calculation Period**: From last CDN settlement epoch + 1 to max reported epoch
- **Settlement Logic**:
  - Retrieves rail ID from FWSS DataSetInfo
  - Fetches rail details from Payments contract to get `lockupFixed`
  - Calculates settleable amount: `min(accumulated_amount, rail.lockupFixed)`
  - Only calls FWSS contract if settleable amount > 0
  - Reduces accumulated CDN amount by settled amount (may leave remainder)
- **State Updates**:
  - Update last CDN settlement epoch to max reported epoch
  - Reduce accumulated amount by settled amount (not reset to zero if partial)
- **Requirements**: None - gracefully skips datasets that cannot be settled
- **Batch Processing**:
  - Processes each dataset independently (non-reverting)
  - Skips uninitialized datasets or those without new usage
  - Skips datasets without valid rail configuration
  - Continues processing even if some datasets cannot be settled
- **Partial Settlement**: Supports partial settlements when `accumulated_amount > lockupFixed`
- **Events**: Emits `CDNSettlement` event with actual settled amount (may be less than accumulated)
- **Independent Operation**: Can be called independently of cache-miss settlement

**Method**: `settleCacheMissPaymentRails(uint256[] dataSetIds)`

- **Access**: Publicly callable (typically called by Storage Providers)
- **Purpose**: Settles cache-miss payment rails for multiple datasets in a single transaction
- **Calculation Period**: From last cache-miss settlement epoch + 1 to max reported epoch
- **Settlement Logic**:
  - Retrieves rail ID from FWSS DataSetInfo
  - Fetches rail details from Payments contract to get `lockupFixed`
  - Calculates settleable amount: `min(accumulated_amount, rail.lockupFixed)`
  - Only calls FWSS contract if settleable amount > 0
  - Reduces accumulated cache-miss amount by settled amount (may leave remainder)
- **State Updates**:
  - Update last cache-miss settlement epoch to max reported epoch
  - Reduce accumulated amount by settled amount (not reset to zero if partial)
- **Requirements**: None - gracefully skips datasets that cannot be settled
- **Batch Processing**:
  - Processes each dataset independently (non-reverting)
  - Skips uninitialized datasets or those without new usage
  - Skips datasets without valid rail configuration
  - Continues processing even if some datasets cannot be settled
- **Partial Settlement**: Supports partial settlements when `accumulated_amount > lockupFixed`
- **Events**: Emits `CacheMissSettlement` event with actual settled amount (may be less than accumulated)
- **Independent Operation**: Can be called independently of CDN settlement

#### Payment Rail Termination
**Method**: `terminateCDNPaymentRails(uint256 dataSetId)`

- **Access**: FilBeamOperator controller only
- **Requirements**: Dataset must be initialized
- **Process**: Forward termination call to FWSS contract
- **Events**: Emits `PaymentRailsTerminated` event

#### Data Access
**Method**: `getDataSetUsage(uint256 dataSetId)`

**Returns**:
- `uint256 cdnAmount`: Current accumulated CDN settlement amount
- `uint256 cacheMissAmount`: Current accumulated cache-miss settlement amount
- `uint256 maxReportedEpoch`: Highest reported epoch (0 indicates uninitialized dataset)
- `uint256 lastCDNSettlementEpoch`: Last CDN settlement epoch
- `uint256 lastCacheMissSettlementEpoch`: Last cache-miss settlement epoch

#### Ownership Management
**Method**: `transferOwnership(address newOwner)`

- **Access**: Contract owner only
- **Requirements**: New owner cannot be zero address
- **Purpose**: Transfer contract ownership

#### FilBeamOperator Controller Management
**Method**: `setFilBeamOperatorController(address _filBeamOperatorController)`

- **Access**: Contract owner only
- **Requirements**: FilBeamOperator controller cannot be zero address
- **Purpose**: Update the authorized address for usage reporting and payment rail termination
- **Events**: Emits `FilBeamOperatorControllerUpdated` event

#### Events
- `UsageReported(uint256 indexed dataSetId, uint256 indexed fromEpoch, uint256 indexed toEpoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed)`
- `CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount)`
- `CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount)`
- `PaymentRailsTerminated(uint256 indexed dataSetId)`
- `FilBeamOperatorControllerUpdated(address indexed oldController, address indexed newController)`

#### Access Control
- **Owner**: Address authorized to manage contract ownership and set FilBeamOperator controller
- **FilBeamOperator Controller**: Address authorized to report usage and terminate payment rails

#### Error Conditions
- `OwnableUnauthorizedAccount(address)`: Caller is not the contract owner
- `Unauthorized()`: Caller is not the FilBeamOperator controller
- `InvalidEpoch()`: Invalid epoch number or ordering (used in usage reporting)
- `InvalidUsageAmount()`: Invalid array lengths in batch operations
- `InvalidRate()`: Invalid rate configuration (zero rates at deployment)
- `InvalidAddress()`: Invalid address (zero address) provided

### Filecoin Warm Storage Service (FWSS) Contract Interface

**Method**: `settleFilBeamPaymentRails(uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount)`
- **Purpose**: Settle CDN or cache-miss payment rails based on calculated amounts
- **Access**: Callable only by FilBeamOperator contract
- **Parameters**: Either cdnAmount or cacheMissAmount will be zero depending on settlement type

**Method**: `terminateCDNPaymentRails(uint256 dataSetId)`
- **Purpose**: Terminate CDN payment rails for a specific dataset
- **Access**: Callable only by FilBeamOperator contract

### Key Implementation Features

#### Rate-Based Settlement
- Immutable rates per byte for both CDN and cache-miss usage set at contract deployment
- Settlement amounts calculated at report time as: `usage * rate`
- Rates cannot be changed after deployment, ensuring predictable pricing

#### Independent Settlement Rails
- CDN and cache-miss settlements operate independently
- Each rail tracks its own settlement epoch
- Allows flexible settlement patterns for different stakeholders

#### Amount Accumulation
- Settlement amounts (calculated at report time) accumulate between settlements
- Only unsettled amounts are stored in contract state
- Settlement reduces accumulated amounts by settled amount (supports partial settlements)

#### Epoch Management
- Strict epoch ordering enforcement
- Prevents duplicate epoch reporting
- Supports batched reporting of multiple epochs via `recordUsageRollups` method for gas efficiency
- Independent epoch tracking per dataset

#### Payments Contract Integration
- Integrates with external Payments contract to enforce lockup limits
- Retrieves rail information including `lockupFixed` to determine maximum settleable amount
- Supports partial settlements when accumulated amount exceeds available lockup
- Gracefully handles missing or invalid rails by skipping settlement
- Multiple settlement calls may be required to fully settle large accumulated amounts
