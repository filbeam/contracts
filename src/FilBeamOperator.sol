// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Errors.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {FilecoinPayV1} from "@filecoin-pay/FilecoinPayV1.sol";
import {FilecoinWarmStorageService} from "@filecoin-services/FilecoinWarmStorageService.sol";
import {FilecoinWarmStorageServiceStateView} from "@filecoin-services/FilecoinWarmStorageServiceStateView.sol";

/// @notice Minimal interface for the shared CDN bandwidth rail settlement added in FWSS.
/// @dev The shared bandwidth rail is keyed by cdnRailId (the subscription identity), so it is
/// settled once per rail rather than per data set. Cache miss continues to be settled per data
/// set via FilecoinWarmStorageService.settleFilBeamPaymentRails.
interface IFilBeamBandwidthSettlement {
    function settleCDNBandwidthRail(uint256 cdnRailId, uint256 cdnAmount) external;
}

contract FilBeamOperator is Ownable2Step {
    /// @notice Cache miss usage accounting, keyed by dataSetId.
    /// @dev Cache miss rails stay per data set because each copy lives on a different provider.
    struct DataSetUsage {
        uint256 cacheMissAmount;
        uint256 maxReportedEpoch;
    }

    address public immutable fwssContractAddress;
    address public immutable fwssStateViewContractAddress;
    address public immutable paymentsContractAddress;
    uint256 public immutable cdnRatePerByte;
    uint256 public immutable cacheMissRatePerByte;
    address public filBeamOperatorController;

    /// @notice Cache miss usage accumulated per data set between settlements.
    mapping(uint256 dataSetId => DataSetUsage) public dataSetUsage;

    /// @notice CDN (bandwidth) usage accumulated per shared bandwidth rail between settlements.
    /// @dev Keyed by cdnRailId so data sets sharing a CDN subscription collapse into one rail.
    mapping(uint256 cdnRailId => uint256 cdnAmount) public cdnRailAmount;

    event UsageReported(
        uint256 indexed dataSetId,
        uint256 indexed fromEpoch,
        uint256 indexed toEpoch,
        uint256 cdnBytesUsed,
        uint256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed cdnRailId, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 cacheMissAmount);

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

    /// @notice Settles shared CDN bandwidth rails directly by rail id.
    /// @dev Canonical bandwidth settlement path: the shared cdnRailId is the subscription identity,
    /// so each rail is settled once with its aggregated amount. The FilBeam worker calls this with
    /// the distinct cdnRailIds it has metered. Anyone can call it to trigger settlement.
    /// @param cdnRailIds Array of shared CDN bandwidth rail ids to settle
    function settleCDNBandwidthRails(uint256[] calldata cdnRailIds) external {
        for (uint256 i = 0; i < cdnRailIds.length; i++) {
            _settleCDNBandwidthRailById(cdnRailIds[i]);
        }
    }

    /// @notice Settles the shared CDN bandwidth rails for multiple data sets.
    /// @dev Convenience path that resolves each data set to its shared cdnRailId and settles once
    /// per distinct rail with the aggregated amount. Because the rail balance is drained on the
    /// first settlement, later data sets that share the same rail in this batch are skipped. Prefer
    /// settleCDNBandwidthRails when the rail ids are already known. Anyone can call this.
    /// @param dataSetIds Array of data set IDs whose shared bandwidth rails should be settled
    function settleCDNPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCDNBandwidthRail(dataSetIds[i]);
        }
    }

    /// @notice Settles cache miss payment rails for multiple data sets
    /// @dev Anyone can call this function to trigger settlement
    /// @param dataSetIds Array of data set IDs to settle
    function settleCacheMissPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCacheMissRail(dataSetIds[i]);
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

        // Cache miss accumulates per data set, bandwidth accumulates onto the shared CDN rail
        // so grouped data sets aggregate into a single bandwidth settlement.
        uint256 cdnRailId =
            FilecoinWarmStorageServiceStateView(fwssStateViewContractAddress).getDataSet(dataSetId).cdnRailId;
        cdnRailAmount[cdnRailId] += cdnAmount;

        usage.cacheMissAmount += cacheMissAmount;
        usage.maxReportedEpoch = toEpoch;

        emit UsageReported(dataSetId, fromEpoch, toEpoch, cdnBytesUsed, cacheMissBytesUsed);
    }

    /// @dev Resolves a data set to its shared bandwidth rail (the subscription identity) and settles it
    /// @param dataSetId The data set ID whose shared bandwidth rail should be settled
    function _settleCDNBandwidthRail(uint256 dataSetId) internal {
        uint256 cdnRailId =
            FilecoinWarmStorageServiceStateView(fwssStateViewContractAddress).getDataSet(dataSetId).cdnRailId;
        _settleCDNBandwidthRailById(cdnRailId);
    }

    /// @dev Settles a shared CDN bandwidth rail once with its aggregated amount
    /// @param cdnRailId The shared bandwidth rail id (subscription identity)
    function _settleCDNBandwidthRailById(uint256 cdnRailId) internal {
        // Early return if no rail configured
        if (cdnRailId == 0) {
            return;
        }

        // Aggregated bandwidth across every data set sharing this rail
        uint256 amount = cdnRailAmount[cdnRailId];

        // Early return if no usage to settle (also collapses repeated rails in a batch)
        if (amount == 0) {
            return;
        }

        // Get the actual amount we can settle based on rail lockup
        uint256 amountToSettle = _getSettleableAmount(cdnRailId, amount);

        // Early return if nothing can be settled (no lockup available)
        if (amountToSettle == 0) {
            return;
        }

        // Settle the shared bandwidth rail once through FWSS
        IFilBeamBandwidthSettlement(fwssContractAddress).settleCDNBandwidthRail(cdnRailId, amountToSettle);
        cdnRailAmount[cdnRailId] -= amountToSettle;
        emit CDNSettlement(cdnRailId, amountToSettle);
    }

    /// @dev Internal function to settle the cache miss rail for a data set
    /// @param dataSetId The data set ID to settle
    function _settleCacheMissRail(uint256 dataSetId) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        uint256 amount = usage.cacheMissAmount;

        // Early return if data set not initialized or no usage to settle
        if (usage.maxReportedEpoch == 0 || amount == 0) {
            return;
        }

        // Get rail ID from FWSS State View
        uint256 railId =
            FilecoinWarmStorageServiceStateView(fwssStateViewContractAddress).getDataSet(dataSetId).cacheMissRailId;

        // Early return if no rail configured
        if (railId == 0) {
            return;
        }

        // Get the actual amount we can settle based on rail lockup
        uint256 amountToSettle = _getSettleableAmount(railId, amount);

        // Early return if nothing can be settled (no lockup available)
        if (amountToSettle == 0) {
            return;
        }

        // Settle cache miss per data set. cdnAmount is 0 so the bandwidth portion is never
        // settled through the per-data-set path (it goes through settleCDNBandwidthRail instead).
        FilecoinWarmStorageService(fwssContractAddress).settleFilBeamPaymentRails(dataSetId, 0, amountToSettle);
        usage.cacheMissAmount -= amountToSettle;
        emit CacheMissSettlement(dataSetId, amountToSettle);
    }

    /// @dev Internal helper to get the settleable amount based on rail lockup
    /// @param railId The payment rail ID
    /// @param requestedAmount The amount requested to settle
    /// @return The amount that can be settled (limited by lockupFixed)
    function _getSettleableAmount(uint256 railId, uint256 requestedAmount) internal view returns (uint256) {
        FilecoinPayV1.RailView memory rail = FilecoinPayV1(paymentsContractAddress).getRail(railId);
        // Return the minimum of requested amount and available lockup
        return requestedAmount > rail.lockupFixed ? rail.lockupFixed : requestedAmount;
    }
}
