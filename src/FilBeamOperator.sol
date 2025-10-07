// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IFWSS.sol";
import "./Errors.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FilBeamOperator is Ownable {
    struct DataSetUsage {
        uint256 cdnBytesUsed;
        uint256 cacheMissBytesUsed;
        uint256 maxReportedEpoch;
        uint256 lastCDNSettlementEpoch;
        uint256 lastCacheMissSettlementEpoch;
    }

    IFWSS public fwss;
    uint256 public cdnRatePerByte;
    uint256 public cacheMissRatePerByte;
    address public filBeamOperatorController;

    mapping(uint256 => DataSetUsage) public dataSetUsage;

    event UsageReported(
        uint256 indexed dataSetId, uint256 indexed epoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    event FilBeamControllerUpdated(address indexed oldController, address indexed newController);

    event CDNRateUpdated(uint256 oldRate, uint256 newRate);

    event CacheMissRateUpdated(uint256 oldRate, uint256 newRate);

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

    function _recordUsageRollup(uint256 dataSetId, uint256 toEpoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed)
        internal
    {
        if (toEpoch == 0) revert InvalidEpoch();

        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (toEpoch <= usage.maxReportedEpoch) revert InvalidEpoch();

        usage.cdnBytesUsed += cdnBytesUsed;
        usage.cacheMissBytesUsed += cacheMissBytesUsed;
        usage.maxReportedEpoch = toEpoch;

        emit UsageReported(dataSetId, toEpoch, cdnBytesUsed, cacheMissBytesUsed);
    }

    function settleCDNPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCDNPaymentRail(dataSetIds[i]);
        }
    }

    function _settleCDNPaymentRail(uint256 dataSetId) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (usage.maxReportedEpoch == 0) revert DataSetNotInitialized();
        if (usage.maxReportedEpoch <= usage.lastCDNSettlementEpoch) revert NoUsageToSettle();

        uint256 fromEpoch = usage.lastCDNSettlementEpoch + 1;
        uint256 toEpoch = usage.maxReportedEpoch;
        uint256 cdnAmount = usage.cdnBytesUsed * cdnRatePerByte;

        if (cdnAmount > 0) {
            fwss.settleFilBeamPaymentRails(dataSetId, cdnAmount, 0);
        }

        usage.lastCDNSettlementEpoch = toEpoch;
        usage.cdnBytesUsed = 0;

        emit CDNSettlement(dataSetId, fromEpoch, toEpoch, cdnAmount);
    }

    function settleCacheMissPaymentRails(uint256[] calldata dataSetIds) external {
        for (uint256 i = 0; i < dataSetIds.length; i++) {
            _settleCacheMissPaymentRail(dataSetIds[i]);
        }
    }

    function _settleCacheMissPaymentRail(uint256 dataSetId) internal {
        DataSetUsage storage usage = dataSetUsage[dataSetId];

        if (usage.maxReportedEpoch == 0) revert DataSetNotInitialized();
        if (usage.maxReportedEpoch <= usage.lastCacheMissSettlementEpoch) revert NoUsageToSettle();

        uint256 fromEpoch = usage.lastCacheMissSettlementEpoch + 1;
        uint256 toEpoch = usage.maxReportedEpoch;
        uint256 cacheMissAmount = usage.cacheMissBytesUsed * cacheMissRatePerByte;

        if (cacheMissAmount > 0) {
            fwss.settleFilBeamPaymentRails(dataSetId, 0, cacheMissAmount);
        }

        usage.lastCacheMissSettlementEpoch = toEpoch;
        usage.cacheMissBytesUsed = 0;

        emit CacheMissSettlement(dataSetId, fromEpoch, toEpoch, cacheMissAmount);
    }

    function terminateCDNPaymentRails(uint256 dataSetId) external onlyFilBeamOperatorController {
        fwss.terminateCDNPaymentRails(dataSetId);

        emit PaymentRailsTerminated(dataSetId);
    }

    function setFilBeamController(address _filBeamOperatorController) external onlyOwner {
        if (_filBeamOperatorController == address(0)) revert InvalidAddress();

        address oldController = filBeamOperatorController;
        filBeamOperatorController = _filBeamOperatorController;

        emit FilBeamControllerUpdated(oldController, _filBeamOperatorController);
    }

    function setCDNRatePerByte(uint256 _cdnRatePerByte) external onlyOwner {
        if (_cdnRatePerByte == 0) revert InvalidRate();

        uint256 oldRate = cdnRatePerByte;
        cdnRatePerByte = _cdnRatePerByte;

        emit CDNRateUpdated(oldRate, _cdnRatePerByte);
    }

    function setCacheMissRatePerByte(uint256 _cacheMissRatePerByte) external onlyOwner {
        if (_cacheMissRatePerByte == 0) revert InvalidRate();

        uint256 oldRate = cacheMissRatePerByte;
        cacheMissRatePerByte = _cacheMissRatePerByte;

        emit CacheMissRateUpdated(oldRate, _cacheMissRatePerByte);
    }

    function getDataSetUsage(uint256 dataSetId)
        external
        view
        returns (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_
        )
    {
        DataSetUsage storage usage = dataSetUsage[dataSetId];
        return (
            usage.cdnBytesUsed,
            usage.cacheMissBytesUsed,
            usage.maxReportedEpoch,
            usage.lastCDNSettlementEpoch,
            usage.lastCacheMissSettlementEpoch
        );
    }
}
