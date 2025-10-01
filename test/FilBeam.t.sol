// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FilBeam} from "../src/FilBeam.sol";
import {MockFWSS} from "../src/mocks/MockFWSS.sol";
import "../src/Errors.sol";

contract FilBeamTest is Test {
    FilBeam public filBeam;
    MockFWSS public mockFWSS;
    address public owner;
    address public filBeamController;
    address public user1;
    address public user2;

    uint256 constant DATA_SET_ID_1 = 1;
    uint256 constant DATA_SET_ID_2 = 2;
    uint256 constant CDN_RATE_PER_BYTE = 100;
    uint256 constant CACHE_MISS_RATE_PER_BYTE = 200;

    event UsageReported(
        uint256 indexed dataSetId, uint256 indexed epoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    event FilBeamControllerUpdated(address indexed oldController, address indexed newController);

    event CDNRateUpdated(uint256 oldRate, uint256 newRate);

    event CacheMissRateUpdated(uint256 oldRate, uint256 newRate);

    function setUp() public {
        owner = address(this);
        filBeamController = makeAddr("filBeamController");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        mockFWSS = new MockFWSS();

        // Deploy FilBeam contract (deployer becomes owner)
        filBeam = new FilBeam(address(mockFWSS), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, filBeamController);

        mockFWSS.setAuthorizedCaller(address(filBeam));
    }

    function test_Initialize() public view {
        assertEq(address(filBeam.fwss()), address(mockFWSS));
        assertEq(filBeam.owner(), owner);
        assertEq(filBeam.filBeamController(), filBeamController);
        assertEq(filBeam.cdnRatePerByte(), CDN_RATE_PER_BYTE);
        assertEq(filBeam.cacheMissRatePerByte(), CACHE_MISS_RATE_PER_BYTE);
    }

    function test_InitializeRevertZeroAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        new FilBeam(address(0), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, filBeamController);
    }

    function test_InitializeRevertZeroRate() public {
        vm.expectRevert(InvalidRate.selector);
        new FilBeam(address(mockFWSS), 0, CACHE_MISS_RATE_PER_BYTE, filBeamController);

        vm.expectRevert(InvalidRate.selector);
        new FilBeam(address(mockFWSS), CDN_RATE_PER_BYTE, 0, filBeamController);
    }

    function test_InitializeRevertZeroFilBeamController() public {
        vm.expectRevert(InvalidAddress.selector);
        new FilBeam(address(mockFWSS), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, address(0));
    }

    function test_ReportUsageRollup() public {
        vm.expectEmit(true, true, false, true);
        emit UsageReported(DATA_SET_ID_1, 1, 1000, 500);

        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 1000);
        assertEq(cacheMissBytesUsed, 500);
        assertEq(maxReportedEpoch, 1);
        assertEq(lastCDNSettlementEpoch_, 0);
        assertEq(lastCacheMissSettlementEpoch_, 0);
    }

    function test_ReportUsageRollupMultipleEpochs() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1500, 750);
        vm.stopPrank();

        (uint256 cdnBytesUsed, uint256 cacheMissBytesUsed, uint256 maxReportedEpoch,,) =
            filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 4500);
        assertEq(cacheMissBytesUsed, 2250);
        assertEq(maxReportedEpoch, 3);
    }

    function test_ReportUsageRollupRevertUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
    }

    function test_ReportUsageRollupRevertZeroEpoch() public {
        vm.prank(filBeamController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 0, 1000, 500);
    }

    function test_ReportUsageRollupRevertDuplicateEpoch() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        vm.prank(filBeamController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 2000, 1000);
    }

    function test_ReportUsageRollupRevertInvalidEpochOrder() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1000, 500);

        vm.prank(filBeamController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
    }

    function test_SettleCDNPaymentRail() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_1, 1, 2, 300000);

        vm.prank(user1);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 0);
        assertEq(cacheMissBytesUsed, 1500);
        assertEq(maxReportedEpoch, 2);
        assertEq(lastCDNSettlementEpoch_, 2);
        assertEq(lastCacheMissSettlementEpoch_, 0);

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(cdnAmount, 300000);
        assertEq(cacheMissAmount, 0);
    }

    function test_SettleCacheMissPaymentRail() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit CacheMissSettlement(DATA_SET_ID_1, 1, 2, 300000);

        vm.prank(user1);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 3000);
        assertEq(cacheMissBytesUsed, 0);
        assertEq(maxReportedEpoch, 2);
        assertEq(lastCDNSettlementEpoch_, 0);
        assertEq(lastCacheMissSettlementEpoch_, 2);

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(cdnAmount, 0);
        assertEq(cacheMissAmount, 300000);
    }

    function test_SettlementRevertDataSetNotInitialized() public {
        vm.expectRevert(DataSetNotInitialized.selector);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        vm.expectRevert(DataSetNotInitialized.selector);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);
    }

    function test_SettlementRevertNoUsageToSettle() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        vm.expectRevert(NoUsageToSettle.selector);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        vm.expectRevert(NoUsageToSettle.selector);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);
    }

    function test_TerminateCDNPaymentRails() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        vm.expectEmit(true, false, false, false);
        emit PaymentRailsTerminated(DATA_SET_ID_1);

        vm.prank(filBeamController);
        filBeam.terminateCDNPaymentRails(DATA_SET_ID_1);

        assertTrue(mockFWSS.terminatedDataSets(DATA_SET_ID_1));
    }

    function test_TerminateCDNPaymentRailsRevertUnauthorized() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        filBeam.terminateCDNPaymentRails(DATA_SET_ID_1);
    }

    function test_TransferOwnership() public {
        filBeam.transferOwnership(user1);
        assertEq(filBeam.owner(), user1);

        vm.prank(user1);
        filBeam.transferOwnership(user2);
        assertEq(filBeam.owner(), user2);
    }

    function test_TransferOwnershipRevertOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        filBeam.transferOwnership(user2);
    }

    function test_TransferOwnershipRevertZeroAddress() public {
        vm.expectRevert();
        filBeam.transferOwnership(address(0));
    }

    function test_MultipleDataSets() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_2, 1, 2000, 1000);
        vm.stopPrank();

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_2);

        assertEq(mockFWSS.getSettlementsCount(), 2);

        (uint256 dataSetId1, uint256 cdnAmount1, uint256 cacheMissAmount1,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId1, DATA_SET_ID_1);
        assertEq(cdnAmount1, 100000);
        assertEq(cacheMissAmount1, 0);

        (uint256 dataSetId2, uint256 cdnAmount2, uint256 cacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(dataSetId2, DATA_SET_ID_2);
        assertEq(cdnAmount2, 0);
        assertEq(cacheMissAmount2, 200000);
    }

    function test_PartialSettlement() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        vm.stopPrank();
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1500, 750);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        assertEq(mockFWSS.getSettlementsCount(), 2);

        (,, uint256 maxReportedEpoch, uint256 lastCDNSettlementEpoch_, uint256 lastCacheMissSettlementEpoch_) =
            filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(maxReportedEpoch, 3);
        assertEq(lastCDNSettlementEpoch_, 2);
        assertEq(lastCacheMissSettlementEpoch_, 3);
    }

    function testFuzz_ReportUsageRollup(uint256 dataSetId, uint256 epoch, uint256 cdnBytes, uint256 cacheMissBytes)
        public
    {
        vm.assume(dataSetId != 0);
        vm.assume(epoch > 0 && epoch < type(uint256).max);
        vm.assume(cdnBytes < type(uint256).max / 2);
        vm.assume(cacheMissBytes < type(uint256).max / 2);

        vm.prank(filBeamController);
        filBeam.reportUsageRollup(dataSetId, epoch, cdnBytes, cacheMissBytes);

        (uint256 cdnBytesUsed, uint256 cacheMissBytesUsed, uint256 maxReportedEpoch,,) =
            filBeam.getDataSetUsage(dataSetId);

        assertEq(cdnBytesUsed, cdnBytes);
        assertEq(cacheMissBytesUsed, cacheMissBytes);
        assertEq(maxReportedEpoch, epoch);
    }

    function test_ZeroUsageReporting() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 0, 0);

        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_1, 1, 1, 0);

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        // No external call should be made when amount is 0
        assertEq(mockFWSS.getSettlementsCount(), 0);

        // Settlement state should still be updated
        (,,, uint256 lastCDNSettlement,) = filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(lastCDNSettlement, 1);
    }

    function test_IndependentSettlement() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1500, 750);
        vm.stopPrank();

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        (
            ,
            uint256 cacheMissBytesUsed1,
            uint256 maxReportedEpoch1,
            uint256 lastCDNSettlementEpoch1,
            uint256 lastCacheMissSettlementEpoch1
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cacheMissBytesUsed1, 2250);
        assertEq(maxReportedEpoch1, 3);
        assertEq(lastCDNSettlementEpoch1, 3);
        assertEq(lastCacheMissSettlementEpoch1, 0);

        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 4, 800, 400);

        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        (
            uint256 cdnBytesUsed2,
            uint256 cacheMissBytesUsed2,
            uint256 maxReportedEpoch2,
            uint256 lastCDNSettlementEpoch2,
            uint256 lastCacheMissSettlementEpoch2
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cdnBytesUsed2, 800);
        assertEq(cacheMissBytesUsed2, 0);
        assertEq(maxReportedEpoch2, 4);
        assertEq(lastCDNSettlementEpoch2, 3);
        assertEq(lastCacheMissSettlementEpoch2, 4);

        assertEq(mockFWSS.getSettlementsCount(), 2);

        (uint256 dataSetId1, uint256 cdnAmount1, uint256 cacheMissAmount1,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId1, DATA_SET_ID_1);
        assertEq(cdnAmount1, 450000);
        assertEq(cacheMissAmount1, 0);

        (uint256 dataSetId2, uint256 cdnAmount2, uint256 cacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(dataSetId2, DATA_SET_ID_1);
        assertEq(cdnAmount2, 0);
        assertEq(cacheMissAmount2, 530000);
    }

    function test_RateCalculations() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);
        (, uint256 cdnAmount1, uint256 cacheMissAmount1,) = mockFWSS.getSettlement(0);
        assertEq(cdnAmount1, 1000 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount1, 0);

        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);
        (, uint256 cdnAmount2, uint256 cacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(cdnAmount2, 0);
        assertEq(cacheMissAmount2, 500 * CACHE_MISS_RATE_PER_BYTE);
    }

    function test_ReportUsageRollupBatch() public {
        uint256[] memory dataSetIds = new uint256[](3);
        uint256[] memory epochs = new uint256[](3);
        uint256[] memory cdnBytesUsed = new uint256[](3);
        uint256[] memory cacheMissBytesUsed = new uint256[](3);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 1;
        cdnBytesUsed[0] = 1000;
        cacheMissBytesUsed[0] = 500;

        dataSetIds[1] = DATA_SET_ID_1;
        epochs[1] = 2;
        cdnBytesUsed[1] = 2000;
        cacheMissBytesUsed[1] = 1000;

        dataSetIds[2] = DATA_SET_ID_2;
        epochs[2] = 1;
        cdnBytesUsed[2] = 1500;
        cacheMissBytesUsed[2] = 750;

        vm.expectEmit(true, true, false, true);
        emit UsageReported(DATA_SET_ID_1, 1, 1000, 500);
        vm.expectEmit(true, true, false, true);
        emit UsageReported(DATA_SET_ID_1, 2, 2000, 1000);
        vm.expectEmit(true, true, false, true);
        emit UsageReported(DATA_SET_ID_2, 1, 1500, 750);

        vm.prank(filBeamController);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);

        (uint256 cdnBytes1, uint256 cacheMissBytes1, uint256 maxEpoch1,,) = filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cdnBytes1, 3000);
        assertEq(cacheMissBytes1, 1500);
        assertEq(maxEpoch1, 2);

        (uint256 cdnBytes2, uint256 cacheMissBytes2, uint256 maxEpoch2,,) = filBeam.getDataSetUsage(DATA_SET_ID_2);
        assertEq(cdnBytes2, 1500);
        assertEq(cacheMissBytes2, 750);
        assertEq(maxEpoch2, 1);
    }

    function test_ReportUsageRollupBatchRevertArrayLengthMismatch() public {
        uint256[] memory dataSetIds = new uint256[](2);
        uint256[] memory epochs = new uint256[](3);
        uint256[] memory cdnBytesUsed = new uint256[](2);
        uint256[] memory cacheMissBytesUsed = new uint256[](2);

        vm.prank(filBeamController);
        vm.expectRevert(InvalidUsageAmount.selector);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchRevertUnauthorized() public {
        uint256[] memory dataSetIds = new uint256[](1);
        uint256[] memory epochs = new uint256[](1);
        uint256[] memory cdnBytesUsed = new uint256[](1);
        uint256[] memory cacheMissBytesUsed = new uint256[](1);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 1;
        cdnBytesUsed[0] = 1000;
        cacheMissBytesUsed[0] = 500;

        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchRevertZeroEpoch() public {
        uint256[] memory dataSetIds = new uint256[](1);
        uint256[] memory epochs = new uint256[](1);
        uint256[] memory cdnBytesUsed = new uint256[](1);
        uint256[] memory cacheMissBytesUsed = new uint256[](1);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 0;
        cdnBytesUsed[0] = 1000;
        cacheMissBytesUsed[0] = 500;

        vm.prank(filBeamController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchRevertDuplicateEpoch() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        uint256[] memory dataSetIds = new uint256[](1);
        uint256[] memory epochs = new uint256[](1);
        uint256[] memory cdnBytesUsed = new uint256[](1);
        uint256[] memory cacheMissBytesUsed = new uint256[](1);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 1;
        cdnBytesUsed[0] = 2000;
        cacheMissBytesUsed[0] = 1000;

        vm.prank(filBeamController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchRevertInvalidEpochOrder() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1000, 500);

        uint256[] memory dataSetIds = new uint256[](1);
        uint256[] memory epochs = new uint256[](1);
        uint256[] memory cdnBytesUsed = new uint256[](1);
        uint256[] memory cacheMissBytesUsed = new uint256[](1);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 2;
        cdnBytesUsed[0] = 2000;
        cacheMissBytesUsed[0] = 1000;

        vm.prank(filBeamController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchEmptyArrays() public {
        uint256[] memory dataSetIds = new uint256[](0);
        uint256[] memory epochs = new uint256[](0);
        uint256[] memory cdnBytesUsed = new uint256[](0);
        uint256[] memory cacheMissBytesUsed = new uint256[](0);

        vm.prank(filBeamController);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchWithSettlement() public {
        uint256[] memory dataSetIds = new uint256[](2);
        uint256[] memory epochs = new uint256[](2);
        uint256[] memory cdnBytesUsed = new uint256[](2);
        uint256[] memory cacheMissBytesUsed = new uint256[](2);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 1;
        cdnBytesUsed[0] = 1000;
        cacheMissBytesUsed[0] = 500;

        dataSetIds[1] = DATA_SET_ID_1;
        epochs[1] = 2;
        cdnBytesUsed[1] = 2000;
        cacheMissBytesUsed[1] = 1000;

        vm.prank(filBeamController);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(cdnAmount, 300000);
        assertEq(cacheMissAmount, 0);
    }

    function test_ReportUsageRollupBatchAtomicity() public {
        uint256[] memory dataSetIds = new uint256[](3);
        uint256[] memory epochs = new uint256[](3);
        uint256[] memory cdnBytesUsed = new uint256[](3);
        uint256[] memory cacheMissBytesUsed = new uint256[](3);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 1;
        cdnBytesUsed[0] = 1000;
        cacheMissBytesUsed[0] = 500;

        dataSetIds[1] = DATA_SET_ID_1;
        epochs[1] = 2;
        cdnBytesUsed[1] = 2000;
        cacheMissBytesUsed[1] = 1000;

        dataSetIds[2] = DATA_SET_ID_1;
        epochs[2] = 0;
        cdnBytesUsed[2] = 1500;
        cacheMissBytesUsed[2] = 750;

        vm.prank(filBeamController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollupBatch(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);

        (
            uint256 cdnBytesUsed1,
            uint256 cacheMissBytesUsed1,
            uint256 maxReportedEpoch1,
            uint256 lastCDNSettlementEpoch1,
            uint256 lastCacheMissSettlementEpoch1
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed1, 0);
        assertEq(cacheMissBytesUsed1, 0);
        assertEq(maxReportedEpoch1, 0);
        assertEq(lastCDNSettlementEpoch1, 0);
        assertEq(lastCacheMissSettlementEpoch1, 0);
    }

    function test_SettleCDNPaymentRailBatch() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        filBeam.reportUsageRollup(DATA_SET_ID_2, 1, 1500, 750);
        vm.stopPrank();

        uint256[] memory dataSetIds = new uint256[](2);
        dataSetIds[0] = DATA_SET_ID_1;
        dataSetIds[1] = DATA_SET_ID_2;

        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_1, 1, 2, 300000);
        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_2, 1, 1, 150000);

        vm.prank(user1);
        filBeam.settleCDNPaymentRailBatch(dataSetIds);

        (uint256 cdnBytes1, uint256 cacheMissBytes1, uint256 maxEpoch1, uint256 lastCDNEpoch1,) =
            filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cdnBytes1, 0);
        assertEq(cacheMissBytes1, 1500);
        assertEq(maxEpoch1, 2);
        assertEq(lastCDNEpoch1, 2);

        (uint256 cdnBytes2, uint256 cacheMissBytes2, uint256 maxEpoch2, uint256 lastCDNEpoch2,) =
            filBeam.getDataSetUsage(DATA_SET_ID_2);
        assertEq(cdnBytes2, 0);
        assertEq(cacheMissBytes2, 750);
        assertEq(maxEpoch2, 1);
        assertEq(lastCDNEpoch2, 1);

        assertEq(mockFWSS.getSettlementsCount(), 2);
        (uint256 dataSetId1, uint256 cdnAmount1, uint256 cacheMissAmount1,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId1, DATA_SET_ID_1);
        assertEq(cdnAmount1, 300000);
        assertEq(cacheMissAmount1, 0);

        (uint256 dataSetId2, uint256 cdnAmount2, uint256 cacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(dataSetId2, DATA_SET_ID_2);
        assertEq(cdnAmount2, 150000);
        assertEq(cacheMissAmount2, 0);
    }

    function test_SettleCacheMissPaymentRailBatch() public {
        vm.startPrank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        filBeam.reportUsageRollup(DATA_SET_ID_2, 1, 1500, 750);
        vm.stopPrank();

        uint256[] memory dataSetIds = new uint256[](2);
        dataSetIds[0] = DATA_SET_ID_1;
        dataSetIds[1] = DATA_SET_ID_2;

        vm.expectEmit(true, false, false, true);
        emit CacheMissSettlement(DATA_SET_ID_1, 1, 2, 300000);
        vm.expectEmit(true, false, false, true);
        emit CacheMissSettlement(DATA_SET_ID_2, 1, 1, 150000);

        vm.prank(user1);
        filBeam.settleCacheMissPaymentRailBatch(dataSetIds);

        (uint256 cdnBytes1, uint256 cacheMissBytes1, uint256 maxEpoch1,, uint256 lastCacheMissEpoch1) =
            filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cdnBytes1, 3000);
        assertEq(cacheMissBytes1, 0);
        assertEq(maxEpoch1, 2);
        assertEq(lastCacheMissEpoch1, 2);

        (uint256 cdnBytes2, uint256 cacheMissBytes2, uint256 maxEpoch2,, uint256 lastCacheMissEpoch2) =
            filBeam.getDataSetUsage(DATA_SET_ID_2);
        assertEq(cdnBytes2, 1500);
        assertEq(cacheMissBytes2, 0);
        assertEq(maxEpoch2, 1);
        assertEq(lastCacheMissEpoch2, 1);

        assertEq(mockFWSS.getSettlementsCount(), 2);
        (uint256 dataSetId1, uint256 cdnAmount1, uint256 cacheMissAmount1,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId1, DATA_SET_ID_1);
        assertEq(cdnAmount1, 0);
        assertEq(cacheMissAmount1, 300000);

        (uint256 dataSetId2, uint256 cdnAmount2, uint256 cacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(dataSetId2, DATA_SET_ID_2);
        assertEq(cdnAmount2, 0);
        assertEq(cacheMissAmount2, 150000);
    }

    function test_SettleCDNPaymentRailBatchEmptyArray() public {
        uint256[] memory dataSetIds = new uint256[](0);
        filBeam.settleCDNPaymentRailBatch(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SettleCacheMissPaymentRailBatchEmptyArray() public {
        uint256[] memory dataSetIds = new uint256[](0);
        filBeam.settleCacheMissPaymentRailBatch(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SettleCDNPaymentRailBatchRevertDataSetNotInitialized() public {
        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        vm.expectRevert(DataSetNotInitialized.selector);
        filBeam.settleCDNPaymentRailBatch(dataSetIds);
    }

    function test_SettleCacheMissPaymentRailBatchRevertDataSetNotInitialized() public {
        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        vm.expectRevert(DataSetNotInitialized.selector);
        filBeam.settleCacheMissPaymentRailBatch(dataSetIds);
    }

    function test_SettleCDNPaymentRailBatchRevertNoUsageToSettle() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        vm.expectRevert(NoUsageToSettle.selector);
        filBeam.settleCDNPaymentRailBatch(dataSetIds);
    }

    function test_SettleCacheMissPaymentRailBatchRevertNoUsageToSettle() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        vm.expectRevert(NoUsageToSettle.selector);
        filBeam.settleCacheMissPaymentRailBatch(dataSetIds);
    }

    function test_SettlementBatchAtomicity() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        uint256[] memory dataSetIds = new uint256[](2);
        dataSetIds[0] = DATA_SET_ID_1;
        dataSetIds[1] = DATA_SET_ID_2;

        vm.expectRevert(DataSetNotInitialized.selector);
        filBeam.settleCDNPaymentRailBatch(dataSetIds);

        (uint256 cdnBytes1, uint256 cacheMissBytes1, uint256 maxEpoch1, uint256 lastCDNEpoch1,) =
            filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cdnBytes1, 1000);
        assertEq(cacheMissBytes1, 500);
        assertEq(maxEpoch1, 1);
        assertEq(lastCDNEpoch1, 0);

        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SetFilBeamController() public {
        address newController = makeAddr("newController");

        vm.expectEmit(true, true, false, true);
        emit FilBeamControllerUpdated(filBeamController, newController);

        filBeam.setFilBeamController(newController);

        assertEq(filBeam.filBeamController(), newController);
    }

    function test_SetFilBeamControllerRevertUnauthorized() public {
        address newController = makeAddr("newController");

        vm.prank(user1);
        vm.expectRevert();
        filBeam.setFilBeamController(newController);
    }

    function test_SetFilBeamControllerRevertZeroAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        filBeam.setFilBeamController(address(0));
    }

    function test_SetFilBeamControllerUpdatesAccess() public {
        address newController = makeAddr("newController");

        filBeam.setFilBeamController(newController);

        vm.prank(filBeamController);
        vm.expectRevert(Unauthorized.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        vm.prank(newController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        (uint256 cdnBytesUsed,,,,) = filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cdnBytesUsed, 1000);
    }

    function test_SetCDNRatePerByte() public {
        uint256 newRate = 150;

        vm.expectEmit(false, false, false, true);
        emit CDNRateUpdated(CDN_RATE_PER_BYTE, newRate);

        filBeam.setCDNRatePerByte(newRate);

        assertEq(filBeam.cdnRatePerByte(), newRate);
    }

    function test_SetCDNRatePerByteRevertUnauthorized() public {
        uint256 newRate = 150;

        vm.prank(user1);
        vm.expectRevert();
        filBeam.setCDNRatePerByte(newRate);
    }

    function test_SetCDNRatePerByteRevertZeroRate() public {
        vm.expectRevert(InvalidRate.selector);
        filBeam.setCDNRatePerByte(0);
    }

    function test_SetCacheMissRatePerByte() public {
        uint256 newRate = 250;

        vm.expectEmit(false, false, false, true);
        emit CacheMissRateUpdated(CACHE_MISS_RATE_PER_BYTE, newRate);

        filBeam.setCacheMissRatePerByte(newRate);

        assertEq(filBeam.cacheMissRatePerByte(), newRate);
    }

    function test_SetCacheMissRatePerByteRevertUnauthorized() public {
        uint256 newRate = 250;

        vm.prank(user1);
        vm.expectRevert();
        filBeam.setCacheMissRatePerByte(newRate);
    }

    function test_SetCacheMissRatePerByteRevertZeroRate() public {
        vm.expectRevert(InvalidRate.selector);
        filBeam.setCacheMissRatePerByte(0);
    }

    function test_RateUpdateAffectsNewSettlements() public {
        vm.prank(filBeamController);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        filBeam.setCDNRatePerByte(150);
        filBeam.setCacheMissRatePerByte(250);

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);
        (, uint256 cdnAmount1,,) = mockFWSS.getSettlement(0);
        assertEq(cdnAmount1, 1000 * 150);

        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);
        (,, uint256 cacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(cacheMissAmount2, 500 * 250);
    }
}
