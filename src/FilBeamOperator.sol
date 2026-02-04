// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Errors.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {FilecoinPayV1} from "@filecoin-pay/FilecoinPayV1.sol";
import {FilecoinWarmStorageService} from "@filecoin-services/FilecoinWarmStorageService.sol";
import {FilecoinWarmStorageServiceStateView} from "@filecoin-services/FilecoinWarmStorageServiceStateView.sol";

contract FilBeamOperator is Ownable2Step {
    struct DataSetUsage {
        uint256 cdnAmount;
        uint256 cacheMissAmount;
        uint256 maxReportedEpoch;
    }

    address public immutable fwssContractAddress;
    address public immutable fwssStateViewContractAddress;
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

    event CDNSettlement(uint256 indexed dataSetId, uint256 settledAmount, uint256 remainingLockup);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 settledAmount, uint256 remainingLockup);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    event FilBeamControllerUpdated(address indexed oldController, address indexed newController);

    event FwssFilBeamControllerChanged(address indexed previousController, address indexed newController);

    /// @notice Initializes the FilBeamOperator contract
    /// @param _fwssAddress Address of the FWSS contract
    /// @param _fwssStateViewAddress Address of the FWSS State View Contract
    /// @param _paymentsAddress Address of the Payments contract
    /// @param _cdnRatePerByte CDN rate per byte in smallest token units
    /// @param _cacheMissRatePerByte Cache miss rate per byte in smallest token units
    /// @param _filBeamOperatorController Address authorized to record usage and terminate payment rails
    constructor(
        address _fwssAddress,
        address _fwssStateViewAddress,
        address _paymentsAddress,
        uint256 _cdnRatePerByte,
        uint256 _cacheMissRatePerByte,
        address _filBeamOperatorController
    ) Ownable(msg.sender) {
        if (_fwssAddress == address(0)) revert InvalidAddress();
        if (_fwssStateViewAddress == address(0)) revert InvalidAddress();
        if (_paymentsAddress == address(0)) revert InvalidAddress();
        if (_cdnRatePerByte == 0 || _cacheMissRatePerByte == 0) revert InvalidRate();
        if (_filBeamOperatorController == address(0)) revert InvalidAddress();

        fwssContractAddress = _fwssAddress;
        fwssStateViewContractAddress = _fwssStateViewAddress;
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

    /// @notice Settles CDN payment rails for multiple data sets
    /// @dev Anyone can call this function to trigger settlement
    /// @param dataSetIds Array of data set IDs to settle
    function settleCDNPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settlePaymentRail(dataSetIds[i], true);
        }
    }

    /// @notice Settles cache miss payment rails for multiple data sets
    /// @dev Anyone can call this function to trigger settlement
    /// @param dataSetIds Array of data set IDs to settle
    function settleCacheMissPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settlePaymentRail(dataSetIds[i], false);
        }
    }

    /// @notice Terminates CDN payment rails for a data set
    /// @dev Can only be called by the FilBeam operator controller
    /// @param dataSetId The data set ID to terminate payment rails for
    function terminateCDNPaymentRails(uint256 dataSetId) external onlyFilBeamOperatorController {
        FilecoinWarmStorageService(fwssContractAddress).terminateCDNService(dataSetId);

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

    /// @notice Transfers the FilBeamController authorization in FWSS to a new operator
    /// @dev Can only be called by the contract owner. This is used during contract upgrades
    /// to transfer control from the current operator to a new operator contract.
    /// @param newController Address of the new FilBeamOperator contract
    function transferFwssFilBeamController(address newController) external onlyOwner {
        if (newController == address(0)) revert InvalidAddress();

        // Transfer the controller authorization in FWSS to the new operator
        FilecoinWarmStorageService(fwssContractAddress).transferFilBeamController(newController);

        emit FwssFilBeamControllerChanged(address(this), newController);
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

    /// @dev Internal function to settle a payment rail (CDN or cache miss)
    /// @param dataSetId The data set ID to settle
    /// @param isCDN True for CDN rail, false for cache miss rail
    function _settlePaymentRail(uint256 dataSetId, bool isCDN) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        // Early return if data set not initialized (no event)
        if (usage.maxReportedEpoch == 0) {
            return;
        }

        // Get rail ID from FWSS State View
        FilecoinWarmStorageService.DataSetInfoView memory dsInfo =
            FilecoinWarmStorageServiceStateView(fwssStateViewContractAddress).getDataSet(dataSetId);
        uint256 railId = isCDN ? dsInfo.cdnRailId : dsInfo.cacheMissRailId;

        // Early return if no rail configured (no event)
        if (railId == 0) {
            return;
        }

        // Get the appropriate amount based on rail type
        uint256 amount = isCDN ? usage.cdnAmount : usage.cacheMissAmount;

        // Get rail info for lockup amount
        FilecoinPayV1.RailView memory rail = FilecoinPayV1(paymentsContractAddress).getRail(railId);

        // Calculate the amount we can settle (limited by lockup)
        uint256 amountToSettle = amount > rail.lockupFixed ? rail.lockupFixed : amount;

        // Calculate remaining lockup after settlement
        uint256 remainingLockup = rail.lockupFixed - amountToSettle;

        // Settle through FWSS only if there's something to settle
        if (amountToSettle > 0) {
            if (isCDN) {
                FilecoinWarmStorageService(fwssContractAddress).settleFilBeamPaymentRails(dataSetId, amountToSettle, 0);
                usage.cdnAmount -= amountToSettle;
            } else {
                FilecoinWarmStorageService(fwssContractAddress).settleFilBeamPaymentRails(dataSetId, 0, amountToSettle);
                usage.cacheMissAmount -= amountToSettle;
            }
        }

        // Always emit event (even if settledAmount is 0)
        if (isCDN) {
            emit CDNSettlement(dataSetId, amountToSettle, remainingLockup);
        } else {
            emit CacheMissSettlement(dataSetId, amountToSettle, remainingLockup);
        }
    }
}
