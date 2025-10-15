// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IFWSS.sol";
import "./Errors.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Payments} from "@filecoin-pay/Payments.sol";

contract FilBeamOperator is Ownable {
    struct DataSetUsage {
        uint256 cdnAmount;
        uint256 cacheMissAmount;
        uint256 maxReportedEpoch;
    }

    address public fwssContractAddress;
    address public immutable paymentsContractAddress;
    uint256 public immutable cdnRatePerByte;
    uint256 public immutable cacheMissRatePerByte;
    address public filBeamOperatorController;

    mapping(uint256 => DataSetUsage) public dataSetUsage;

    event UsageReported(
        uint256 indexed dataSetId,
        uint256 indexed fromEpoch,
        uint256 indexed toEpoch,
        uint256 cdnBytesUsed,
        uint256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed dataSetId, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 cacheMissAmount);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    event FilBeamControllerUpdated(address indexed oldController, address indexed newController);

    /// @notice Initializes the FilBeamOperator contract
    /// @param fwssAddress Address of the FWSS contract
    /// @param _paymentsAddress Address of the Payments contract
    /// @param _cdnRatePerByte CDN rate per byte in smallest token units
    /// @param _cacheMissRatePerByte Cache miss rate per byte in smallest token units
    /// @param _filBeamOperatorController Address authorized to record usage and terminate payment rails
    constructor(
        address fwssAddress,
        address _paymentsAddress,
        uint256 _cdnRatePerByte,
        uint256 _cacheMissRatePerByte,
        address _filBeamOperatorController
    ) Ownable(msg.sender) {
        if (fwssAddress == address(0)) revert InvalidAddress();
        if (_paymentsAddress == address(0)) revert InvalidAddress();
        if (_cdnRatePerByte == 0 || _cacheMissRatePerByte == 0) revert InvalidRate();
        if (_filBeamOperatorController == address(0)) revert InvalidAddress();

        fwssContractAddress = fwssAddress;
        paymentsContractAddress = _paymentsAddress;
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
    /// @param toEpoch Epoch number up to which usage is reported for all data sets
    /// @param dataSetIds Array of data set IDs
    /// @param cdnBytesUsed Array of CDN egress bytes used for each data set
    /// @param cacheMissBytesUsed Array of cache miss egress bytes used for each data set
    function recordUsageRollups(
        uint256 toEpoch,
        uint256[] calldata dataSetIds,
        uint256[] calldata cdnBytesUsed,
        uint256[] calldata cacheMissBytesUsed
    ) external onlyFilBeamOperatorController {
        uint256 length = dataSetIds.length;
        if (length != cdnBytesUsed.length || length != cacheMissBytesUsed.length) {
            revert InvalidUsageAmount();
        }

        for (uint256 i = 0; i < length; i++) {
            _recordUsageRollup(dataSetIds[i], toEpoch, cdnBytesUsed[i], cacheMissBytesUsed[i]);
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

        uint256 fromEpoch = usage.maxReportedEpoch + 1;

        // Calculate amounts using current rates at report time
        uint256 cdnAmount = cdnBytesUsed * cdnRatePerByte;
        uint256 cacheMissAmount = cacheMissBytesUsed * cacheMissRatePerByte;

        usage.cdnAmount += cdnAmount;
        usage.cacheMissAmount += cacheMissAmount;
        usage.maxReportedEpoch = toEpoch;

        emit UsageReported(dataSetId, fromEpoch, toEpoch, cdnBytesUsed, cacheMissBytesUsed);
    }

    /// @dev Internal helper to get the settleable amount based on rail lockup
    /// @param railId The payment rail ID
    /// @param requestedAmount The amount requested to settle
    /// @return The amount that can be settled (limited by lockupFixed)
    function _getSettleableAmount(uint256 railId, uint256 requestedAmount) internal view returns (uint256) {
        Payments.RailView memory rail = Payments(paymentsContractAddress).getRail(railId);
        // Return the minimum of requested amount and available lockup
        return requestedAmount > rail.lockupFixed ? rail.lockupFixed : requestedAmount;
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

        // Early return if data set not initialized or no usage to settle
        if (usage.maxReportedEpoch == 0 || usage.cdnAmount == 0) {
            return;
        }

        // Get rail ID from FWSS
        IFWSS fwss = IFWSS(fwssContractAddress);
        IFWSS.DataSetInfo memory dsInfo = fwss.getDataSetInfo(dataSetId);

        // Early return if no CDN rail configured
        if (dsInfo.cdnRailId == 0) {
            return;
        }

        // Get the actual amount we can settle based on rail lockup
        uint256 amountToSettle = _getSettleableAmount(dsInfo.cdnRailId, usage.cdnAmount);

        // Early return if nothing can be settled (no lockup available)
        if (amountToSettle == 0) {
            return;
        }

        // Settle the amount and update remaining balance
        fwss.settleFilBeamPaymentRails(dataSetId, amountToSettle, 0);
        usage.cdnAmount -= amountToSettle;

        emit CDNSettlement(dataSetId, amountToSettle);
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

        // Early return if data set not initialized or no usage to settle
        if (usage.maxReportedEpoch == 0 || usage.cacheMissAmount == 0) {
            return;
        }

        // Get rail ID from FWSS
        IFWSS fwss = IFWSS(fwssContractAddress);
        IFWSS.DataSetInfo memory dsInfo = fwss.getDataSetInfo(dataSetId);

        // Early return if no cache miss rail configured
        if (dsInfo.cacheMissRailId == 0) {
            return;
        }

        // Get the actual amount we can settle based on rail lockup
        uint256 amountToSettle = _getSettleableAmount(dsInfo.cacheMissRailId, usage.cacheMissAmount);

        // Early return if nothing can be settled (no lockup available)
        if (amountToSettle == 0) {
            return;
        }

        // Settle the amount and update remaining balance
        fwss.settleFilBeamPaymentRails(dataSetId, 0, amountToSettle);
        usage.cacheMissAmount -= amountToSettle;

        emit CacheMissSettlement(dataSetId, amountToSettle);
    }

    /// @notice Terminates CDN payment rails for a data set
    /// @dev Can only be called by the FilBeam operator controller
    /// @param dataSetId The data set ID to terminate payment rails for
    function terminateCDNPaymentRails(uint256 dataSetId) external onlyFilBeamOperatorController {
        IFWSS(fwssContractAddress).terminateCDNPaymentRails(dataSetId);

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
}
