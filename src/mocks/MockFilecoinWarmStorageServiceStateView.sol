// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {FilecoinWarmStorageService} from "@filecoin-services/FilecoinWarmStorageService.sol";

contract MockFilecoinWarmStorageServiceStateView {
    mapping(uint256 => FilecoinWarmStorageService.DataSetInfoView) private _dataSetInfos;

    constructor() {}

    // Mock the getDataSet function to return mock data
    function getDataSet(uint256 dataSetId) public view returns (FilecoinWarmStorageService.DataSetInfoView memory) {
        return _dataSetInfos[dataSetId];
    }

    // Helper function to set mock data for testing
    function setDataSetInfo(uint256 dataSetId, FilecoinWarmStorageService.DataSetInfoView memory dataSetInfo) public {
        _dataSetInfos[dataSetId] = dataSetInfo;
    }
}
