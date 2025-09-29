// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IFWSS {
    function settleCDNPaymentRails(uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount) external;

    function terminateCDNPaymentRails(uint256 dataSetId) external;
}
