// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IFWSS.sol";
import "./Errors.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FilBeamOperator is Ownable {
    struct DataSetUsage {
        uint256 cdnAmount;
        uint256 cacheMissAmount;
        uint256 maxReportedEpoch;
        uint256 lastCDNSettlementEpoch;
        uint256 lastCacheMissSettlementEpoch;
    }

    IFWSS public fwss;
    uint256 public immutable cdnRatePerByte;
    uint256 public immutable cacheMissRatePerByte;
    address public filBeamOperatorController;

    mapping(uint256 => DataSetUsage) public dataSetUsage;

    event UsageReported(
        uint256 indexed dataSetId, uint256 indexed epoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    event FilBeamControllerUpdated(address indexed oldController, address indexed newController);

    /// @notice Initializes the FilBeamOperator contract
    /// @param fwssAddress Address of the FWSS contract
    /// @param _cdnRatePerByte CDN rate per byte in smallest token units
    /// @param _cacheMissRatePerByte Cache miss rate per byte in smallest token units
    /// @param _filBeamOperatorController Address authorized to record usage and terminate payment rails
    constructor(
        address fwssAddress,
        uint256 _cdnRatePerByte,
        uint256 _cacheMissRatePerByte,
        address _filBeamOperatorController
    ) Ownable(msg.sender) {
        if (fwssAddress == address(0)) revert InvalidAddress();
        if (_cdnRatePerByte == 0 || _cacheMissRatePerByte == 0) revert InvalidRate();
        if (_filBeamOperatorController == address(0)) revert InvalidAddress();

        fwss = IFWSS(fwssAddress);
        cdnRatePerByte = _cdnRatePerByte;
        cacheMissRatePerByte = _cacheMissRatePerByte;
        filBeamOperatorController = _filBeamOperatorController;
    }

    modifier onlyFilBeamOperatorController() {
        if (msg.sender != filBeamOperatorController) revert Unauthorized();
        _;
    }

    /// @notice Records usage rollups for multiple data sets
    /// @dev Can only be called by the FilBeam operator controller
    /// @param dataSetIds Array of data set IDs
    /// @param epochs Array of epoch numbers
    /// @param cdnBytesUsed Array of CDN egress bytes used for each data set
    /// @param cacheMissBytesUsed Array of cache miss egress bytes used for each data set
    function recordUsageRollups(
        uint256[] calldata dataSetIds,
        uint256[] calldata epochs,
        uint256[] calldata cdnBytesUsed,
        uint256[] calldata cacheMissBytesUsed
    ) external onlyFilBeamOperatorController {
        uint256 length = dataSetIds.length;
        if (length != epochs.length || length != cdnBytesUsed.length || length != cacheMissBytesUsed.length) {
            revert InvalidUsageAmount();
        }

        for (uint256 i = 0; i < length; i++) {
            _recordUsageRollup(dataSetIds[i], epochs[i], cdnBytesUsed[i], cacheMissBytesUsed[i]);
        }
    }

    /// @dev Internal function to record usage for a single data set
    /// @param dataSetId The data set ID
    /// @param toEpoch The epoch number to record usage for
    /// @param cdnBytesUsed CDN egress bytes used
    /// @param cacheMissBytesUsed Cache miss egress bytes used
    function _recordUsageRollup(uint256 dataSetId, uint256 toEpoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed)
        internal
    {
        if (toEpoch == 0) revert InvalidEpoch();

        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (toEpoch <= usage.maxReportedEpoch) revert InvalidEpoch();

        // Calculate amounts using current rates at report time
        uint256 cdnAmount = cdnBytesUsed * cdnRatePerByte;
        uint256 cacheMissAmount = cacheMissBytesUsed * cacheMissRatePerByte;

        usage.cdnAmount += cdnAmount;
        usage.cacheMissAmount += cacheMissAmount;
        usage.maxReportedEpoch = toEpoch;

        emit UsageReported(dataSetId, toEpoch, cdnBytesUsed, cacheMissBytesUsed);
    }

    /// @notice Settles CDN payment rails for multiple data sets
    /// @dev Anyone can call this function to trigger settlement
    /// @param dataSetIds Array of data set IDs to settle
    function settleCDNPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCDNPaymentRail(dataSetIds[i]);
        }
    }

    /// @dev Internal function to settle CDN payment rail for a single data set
    /// @param dataSetId The data set ID to settle
    function _settleCDNPaymentRail(uint256 dataSetId) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (usage.maxReportedEpoch == 0) revert DataSetNotInitialized();
        if (usage.maxReportedEpoch <= usage.lastCDNSettlementEpoch) revert NoUsageToSettle();

        uint256 fromEpoch = usage.lastCDNSettlementEpoch + 1;
        uint256 toEpoch = usage.maxReportedEpoch;
        uint256 cdnAmount = usage.cdnAmount;

        if (cdnAmount > 0) {
            fwss.settleFilBeamPaymentRails(dataSetId, cdnAmount, 0);
        }

        usage.lastCDNSettlementEpoch = toEpoch;
        usage.cdnAmount = 0;

        emit CDNSettlement(dataSetId, fromEpoch, toEpoch, cdnAmount);
    }

    /// @notice Settles cache miss payment rails for multiple data sets
    /// @dev Anyone can call this function to trigger settlement
    /// @param dataSetIds Array of data set IDs to settle
    function settleCacheMissPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCacheMissPaymentRail(dataSetIds[i]);
        }
    }

    /// @dev Internal function to settle cache miss payment rail for a single data set
    /// @param dataSetId The data set ID to settle
    function _settleCacheMissPaymentRail(uint256 dataSetId) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (usage.maxReportedEpoch == 0) revert DataSetNotInitialized();
        if (usage.maxReportedEpoch <= usage.lastCacheMissSettlementEpoch) revert NoUsageToSettle();

        uint256 fromEpoch = usage.lastCacheMissSettlementEpoch + 1;
        uint256 toEpoch = usage.maxReportedEpoch;
        uint256 cacheMissAmount = usage.cacheMissAmount;

        if (cacheMissAmount > 0) {
            fwss.settleFilBeamPaymentRails(dataSetId, 0, cacheMissAmount);
        }

        usage.lastCacheMissSettlementEpoch = toEpoch;
        usage.cacheMissAmount = 0;

        emit CacheMissSettlement(dataSetId, fromEpoch, toEpoch, cacheMissAmount);
    }

    /// @notice Terminates CDN payment rails for a data set
    /// @dev Can only be called by the FilBeam operator controller
    /// @param dataSetId The data set ID to terminate payment rails for
    function terminateCDNPaymentRails(uint256 dataSetId) external onlyFilBeamOperatorController {
        fwss.terminateCDNPaymentRails(dataSetId);

        emit PaymentRailsTerminated(dataSetId);
    }

    /// @notice Updates the FilBeamOperator controller address
    /// @dev Can only be called by the contract owner
    /// @param _filBeamOperatorController New controller address
    function setFilBeamOperatorController(address _filBeamOperatorController) external onlyOwner {
        if (_filBeamOperatorController == address(0)) revert InvalidAddress();

        address oldController = filBeamOperatorController;
        filBeamOperatorController = _filBeamOperatorController;

        emit FilBeamControllerUpdated(oldController, _filBeamOperatorController);
    }

    /// @notice Retrieves usage data for a specific data set
    /// @param dataSetId The data set ID to query
    /// @return cdnAmount Accumulated CDN amount pending settlement
    /// @return cacheMissAmount Accumulated cache miss amount pending settlement
    /// @return maxReportedEpoch The highest epoch number reported for this data set
    /// @return lastCDNSettlementEpoch_ The last epoch for which CDN payment was settled
    /// @return lastCacheMissSettlementEpoch_ The last epoch for which cache miss payment was settled
    function getDataSetUsage(uint256 dataSetId)
        external
        view
        returns (
            uint256 cdnAmount,
            uint256 cacheMissAmount,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_
        )
    {
        DataSetUsage storage usage = dataSetUsage[dataSetId];
        return (
            usage.cdnAmount,
            usage.cacheMissAmount,
            usage.maxReportedEpoch,
            usage.lastCDNSettlementEpoch,
            usage.lastCacheMissSettlementEpoch
        );
    }
}
