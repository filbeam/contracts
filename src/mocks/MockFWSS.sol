// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract MockFWSS {
    struct Settlement {
        uint256 dataSetId;
        uint256 cdnAmount;
        uint256 cacheMissAmount;
        uint256 timestamp;
    }

    struct BandwidthSettlement {
        uint256 cdnRailId;
        uint256 cdnAmount;
        uint256 timestamp;
    }

    Settlement[] public settlements;
    BandwidthSettlement[] public bandwidthSettlements;
    mapping(uint256 => bool) public terminatedDataSets;
    address public authorizedCaller;
    address public usdfcTokenAddress;
    address public paymentsContractAddress;

    event PaymentRailsSettled(uint256 indexed dataSetId, uint256 cdnAmount, uint256 cacheMissAmount);
    event CDNBandwidthRailSettled(uint256 indexed cdnRailId, uint256 cdnAmount);
    event PaymentRailsTerminated(uint256 indexed dataSetId);
    event FilBeamControllerChanged(address indexed oldController, address indexed newController);

    error UnauthorizedCaller();

    modifier onlyAuthorized() {
        if (msg.sender != authorizedCaller) revert UnauthorizedCaller();
        _;
    }

    constructor() {
        authorizedCaller = msg.sender;
    }

    function setAuthorizedCaller(address caller) external {
        authorizedCaller = caller;
    }

    function setUsdfcTokenAddress(address _usdfcTokenAddress) external {
        usdfcTokenAddress = _usdfcTokenAddress;
    }

    function setPaymentsContractAddress(address _paymentsContractAddress) external {
        paymentsContractAddress = _paymentsContractAddress;
    }

    function settleFilBeamPaymentRails(uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount)
        external
        onlyAuthorized
    {
        settlements.push(
            Settlement({
                dataSetId: dataSetId, cdnAmount: cdnAmount, cacheMissAmount: cacheMissAmount, timestamp: block.timestamp
            })
        );

        emit PaymentRailsSettled(dataSetId, cdnAmount, cacheMissAmount);
    }

    function settleCDNBandwidthRail(uint256 cdnRailId, uint256 cdnAmount) external onlyAuthorized {
        bandwidthSettlements.push(
            BandwidthSettlement({cdnRailId: cdnRailId, cdnAmount: cdnAmount, timestamp: block.timestamp})
        );

        emit CDNBandwidthRailSettled(cdnRailId, cdnAmount);
    }

    function terminateCDNService(uint256 dataSetId) external onlyAuthorized {
        terminatedDataSets[dataSetId] = true;
        emit PaymentRailsTerminated(dataSetId);
    }

    function getSettlementsCount() external view returns (uint256) {
        return settlements.length;
    }

    function getSettlement(uint256 index)
        external
        view
        returns (uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount, uint256 timestamp)
    {
        Settlement storage settlement = settlements[index];
        return (settlement.dataSetId, settlement.cdnAmount, settlement.cacheMissAmount, settlement.timestamp);
    }

    function getBandwidthSettlementsCount() external view returns (uint256) {
        return bandwidthSettlements.length;
    }

    function getBandwidthSettlement(uint256 index)
        external
        view
        returns (uint256 cdnRailId, uint256 cdnAmount, uint256 timestamp)
    {
        BandwidthSettlement storage settlement = bandwidthSettlements[index];
        return (settlement.cdnRailId, settlement.cdnAmount, settlement.timestamp);
    }

    function transferFilBeamController(address newController) external onlyAuthorized {
        require(newController != address(0), "Zero address");
        address oldController = authorizedCaller;
        authorizedCaller = newController;
        emit FilBeamControllerChanged(oldController, newController);
    }
}
