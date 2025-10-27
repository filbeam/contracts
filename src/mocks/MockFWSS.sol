// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IFWSS.sol";

contract MockFWSS is IFWSS {
    struct Settlement {
        uint256 dataSetId;
        uint256 cdnAmount;
        uint256 cacheMissAmount;
        uint256 timestamp;
    }

    Settlement[] public settlements;
    mapping(uint256 => bool) public terminatedDataSets;
    mapping(uint256 => DataSetInfo) public dataSetInfos;
    address public authorizedCaller;
    address public usdfcTokenAddress;

    event PaymentRailsSettled(uint256 indexed dataSetId, uint256 cdnAmount, uint256 cacheMissAmount);
    event PaymentRailsTerminated(uint256 indexed dataSetId);

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

    function terminateCDNPaymentRails(uint256 dataSetId) external onlyAuthorized {
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

    function getDataSetInfo(uint256 dataSetId) external view returns (DataSetInfo memory) {
        return dataSetInfos[dataSetId];
    }

    function setDataSetInfo(uint256 dataSetId, DataSetInfo memory info) external {
        dataSetInfos[dataSetId] = info;
    }
}
