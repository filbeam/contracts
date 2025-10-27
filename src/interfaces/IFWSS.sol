// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IFWSS {
    struct DataSetInfo {
        uint256 pdpRailId; // ID of the PDP payment rail
        uint256 cacheMissRailId; // For CDN add-on: ID of the cache miss payment rail
        uint256 cdnRailId; // For CDN add-on: ID of the CDN payment rail
        address payer; // Address paying for storage
        address payee; // SP's beneficiary address
        address serviceProvider; // Current service provider of the dataset
        uint256 commissionBps; // Commission rate for this data set
        uint256 clientDataSetId; // ClientDataSetID
        uint256 pdpEndEpoch; // 0 if PDP rail are not terminated
        uint256 providerId; // Provider ID from the ServiceProviderRegistry
    }

    function getDataSetInfo(uint256 dataSetId) external view returns (DataSetInfo memory);

    function settleFilBeamPaymentRails(uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount) external;

    function terminateCDNPaymentRails(uint256 dataSetId) external;

    function usdfcTokenAddress() external view returns (address);
}
