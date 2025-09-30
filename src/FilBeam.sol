// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IFWSS.sol";
import "./Errors.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FilBeam is Ownable {
    struct DataSetUsage {
        uint256 cdnBytesUsed;
        uint256 cacheMissBytesUsed;
        uint256 maxReportedEpoch;
        uint256 lastCDNSettlementEpoch;
        uint256 lastCacheMissSettlementEpoch;
        bool isInitialized;
    }

    IFWSS public fwss;
    uint256 public cdnRatePerByte;
    uint256 public cacheMissRatePerByte;
    address public filBeamController;

    mapping(uint256 => DataSetUsage) public dataSetUsage;

    event UsageReported(
        uint256 indexed dataSetId, uint256 indexed epoch, int256 cdnBytesUsed, int256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    event FilBeamControllerUpdated(address indexed oldController, address indexed newController);

    constructor(
        address fwssAddress,
        uint256 _cdnRatePerByte,
        uint256 _cacheMissRatePerByte,
        address initialOwner,
        address _filBeamController
    ) Ownable(initialOwner) {
        if (fwssAddress == address(0)) revert InvalidUsageAmount();
        if (_cdnRatePerByte == 0 || _cacheMissRatePerByte == 0) revert InvalidRate();
        if (initialOwner == address(0)) revert InvalidUsageAmount();
        if (_filBeamController == address(0)) revert InvalidUsageAmount();

        fwss = IFWSS(fwssAddress);
        cdnRatePerByte = _cdnRatePerByte;
        cacheMissRatePerByte = _cacheMissRatePerByte;
        filBeamController = _filBeamController;
    }

    modifier onlyFilBeamController() {
        if (msg.sender != filBeamController) revert Unauthorized();
        _;
    }

    function reportUsageRollup(uint256 dataSetId, uint256 newEpoch, int256 cdnBytesUsed, int256 cacheMissBytesUsed)
        external
        onlyFilBeamController
    {
        _reportUsageRollup(dataSetId, newEpoch, cdnBytesUsed, cacheMissBytesUsed);
    }

    function reportUsageRollupBatch(
        uint256[] calldata dataSetIds,
        uint256[] calldata epochs,
        int256[] calldata cdnBytesUsed,
        int256[] calldata cacheMissBytesUsed
    ) external onlyFilBeamController {
        uint256 length = dataSetIds.length;
        if (length != epochs.length || length != cdnBytesUsed.length || length != cacheMissBytesUsed.length) {
            revert InvalidUsageAmount();
        }

        for (uint256 i = 0; i < length; i++) {
            _reportUsageRollup(dataSetIds[i], epochs[i], cdnBytesUsed[i], cacheMissBytesUsed[i]);
        }
    }

    function _reportUsageRollup(uint256 dataSetId, uint256 newEpoch, int256 cdnBytesUsed, int256 cacheMissBytesUsed)
        internal
    {
        if (newEpoch == 0) revert InvalidEpoch();
        if (cdnBytesUsed < 0 || cacheMissBytesUsed < 0) revert InvalidUsageAmount();

        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (!usage.isInitialized) {
            usage.isInitialized = true;
        }

        if (newEpoch <= usage.maxReportedEpoch) revert InvalidEpoch();

        usage.cdnBytesUsed += uint256(cdnBytesUsed);
        usage.cacheMissBytesUsed += uint256(cacheMissBytesUsed);
        usage.maxReportedEpoch = newEpoch;

        emit UsageReported(dataSetId, newEpoch, cdnBytesUsed, cacheMissBytesUsed);
    }

    function settleCDNPaymentRail(uint256 dataSetId) external {
        _settleCDNPaymentRail(dataSetId);
    }

    function settleCDNPaymentRailBatch(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCDNPaymentRail(dataSetIds[i]);
        }
    }

    function _settleCDNPaymentRail(uint256 dataSetId) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (!usage.isInitialized) revert DataSetNotInitialized();
        if (usage.maxReportedEpoch <= usage.lastCDNSettlementEpoch) revert NoUsageToSettle();

        uint256 fromEpoch = usage.lastCDNSettlementEpoch + 1;
        uint256 toEpoch = usage.maxReportedEpoch;
        uint256 cdnAmount = usage.cdnBytesUsed * cdnRatePerByte;

        usage.lastCDNSettlementEpoch = toEpoch;
        usage.cdnBytesUsed = 0;

        fwss.settleCDNPaymentRails(dataSetId, cdnAmount, 0);

        emit CDNSettlement(dataSetId, fromEpoch, toEpoch, cdnAmount);
    }

    function settleCacheMissPaymentRail(uint256 dataSetId) external {
        _settleCacheMissPaymentRail(dataSetId);
    }

    function settleCacheMissPaymentRailBatch(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCacheMissPaymentRail(dataSetIds[i]);
        }
    }

    function _settleCacheMissPaymentRail(uint256 dataSetId) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (!usage.isInitialized) revert DataSetNotInitialized();
        if (usage.maxReportedEpoch <= usage.lastCacheMissSettlementEpoch) revert NoUsageToSettle();

        uint256 fromEpoch = usage.lastCacheMissSettlementEpoch + 1;
        uint256 toEpoch = usage.maxReportedEpoch;
        uint256 cacheMissAmount = usage.cacheMissBytesUsed * cacheMissRatePerByte;

        usage.lastCacheMissSettlementEpoch = toEpoch;
        usage.cacheMissBytesUsed = 0;

        fwss.settleCDNPaymentRails(dataSetId, 0, cacheMissAmount);

        emit CacheMissSettlement(dataSetId, fromEpoch, toEpoch, cacheMissAmount);
    }

    function terminateCDNPaymentRails(uint256 dataSetId) external onlyFilBeamController {
        if (!dataSetUsage[dataSetId].isInitialized) revert DataSetNotInitialized();

        fwss.terminateCDNPaymentRails(dataSetId);

        emit PaymentRailsTerminated(dataSetId);
    }

    function setFilBeamController(address _filBeamController) external onlyOwner {
        if (_filBeamController == address(0)) revert InvalidUsageAmount();

        address oldController = filBeamController;
        filBeamController = _filBeamController;

        emit FilBeamControllerUpdated(oldController, _filBeamController);
    }

    function getDataSetUsage(uint256 dataSetId)
        external
        view
        returns (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_,
            bool isInitialized
        )
    {
        DataSetUsage storage usage = dataSetUsage[dataSetId];
        return (
            usage.cdnBytesUsed,
            usage.cacheMissBytesUsed,
            usage.maxReportedEpoch,
            usage.lastCDNSettlementEpoch,
            usage.lastCacheMissSettlementEpoch,
            usage.isInitialized
        );
    }
}
