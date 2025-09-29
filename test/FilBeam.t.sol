// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FilBeam} from "../src/FilBeam.sol";
import {MockFWSS} from "../src/mocks/MockFWSS.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Errors.sol";

contract FilBeamTest is Test {
    FilBeam public filBeam;
    FilBeam public implementation;
    ERC1967Proxy public proxy;
    MockFWSS public mockFWSS;
    address public owner;
    address public user1;
    address public user2;

    uint256 constant DATA_SET_ID_1 = 1;
    uint256 constant DATA_SET_ID_2 = 2;
    uint256 constant CDN_RATE_PER_BYTE = 100;
    uint256 constant CACHE_MISS_RATE_PER_BYTE = 200;

    event UsageReported(
        uint256 indexed dataSetId, uint256 indexed epoch, int256 cdnBytesUsed, int256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 fromEpoch, uint256 toEpoch, uint256 cacheMissAmount);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        mockFWSS = new MockFWSS();

        // Deploy implementation
        implementation = new FilBeam();

        // Encode initialize call
        bytes memory initData =
            abi.encodeCall(FilBeam.initialize, (address(mockFWSS), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, owner));

        // Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Cast proxy to FilBeam interface
        filBeam = FilBeam(address(proxy));

        mockFWSS.setAuthorizedCaller(address(filBeam));
    }

    function test_Initialize() public view {
        assertEq(address(filBeam.fwss()), address(mockFWSS));
        assertEq(filBeam.owner(), owner);
        assertEq(filBeam.cdnRatePerByte(), CDN_RATE_PER_BYTE);
        assertEq(filBeam.cacheMissRatePerByte(), CACHE_MISS_RATE_PER_BYTE);
    }

    function test_InitializeRevertZeroAddress() public {
        FilBeam newImplementation = new FilBeam();

        bytes memory initData =
            abi.encodeCall(FilBeam.initialize, (address(0), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, owner));

        vm.expectRevert(InvalidUsageAmount.selector);
        new ERC1967Proxy(address(newImplementation), initData);
    }

    function test_InitializeRevertZeroRate() public {
        FilBeam newImplementation = new FilBeam();

        bytes memory initData1 =
            abi.encodeCall(FilBeam.initialize, (address(mockFWSS), 0, CACHE_MISS_RATE_PER_BYTE, owner));

        vm.expectRevert(InvalidRate.selector);
        new ERC1967Proxy(address(newImplementation), initData1);

        bytes memory initData2 = abi.encodeCall(FilBeam.initialize, (address(mockFWSS), CDN_RATE_PER_BYTE, 0, owner));

        vm.expectRevert(InvalidRate.selector);
        new ERC1967Proxy(address(newImplementation), initData2);
    }

    function test_InitializeRevertZeroOwner() public {
        FilBeam newImplementation = new FilBeam();

        bytes memory initData = abi.encodeCall(
            FilBeam.initialize, (address(mockFWSS), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, address(0))
        );

        vm.expectRevert(InvalidUsageAmount.selector);
        new ERC1967Proxy(address(newImplementation), initData);
    }

    function test_ReportUsageRollup() public {
        vm.expectEmit(true, true, false, true);
        emit UsageReported(DATA_SET_ID_1, 1, 1000, 500);

        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_,
            bool isInitialized
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 1000);
        assertEq(cacheMissBytesUsed, 500);
        assertEq(maxReportedEpoch, 1);
        assertEq(lastCDNSettlementEpoch_, 0);
        assertEq(lastCacheMissSettlementEpoch_, 0);
        assertTrue(isInitialized);
        assertTrue(filBeam.epochReported(DATA_SET_ID_1, 1));
    }

    function test_ReportUsageRollupMultipleEpochs() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1500, 750);

        (uint256 cdnBytesUsed, uint256 cacheMissBytesUsed, uint256 maxReportedEpoch,,,) =
            filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 4500);
        assertEq(cacheMissBytesUsed, 2250);
        assertEq(maxReportedEpoch, 3);
    }

    function test_ReportUsageRollupRevertOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
    }

    function test_ReportUsageRollupRevertZeroEpoch() public {
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 0, 1000, 500);
    }

    function test_ReportUsageRollupRevertNegativeUsage() public {
        vm.expectRevert(InvalidUsageAmount.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, -1000, 500);

        vm.expectRevert(InvalidUsageAmount.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, -500);
    }

    function test_ReportUsageRollupRevertDuplicateEpoch() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        vm.expectRevert(EpochAlreadyReported.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 2000, 1000);
    }

    function test_ReportUsageRollupRevertInvalidEpochOrder() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1000, 500);

        vm.expectRevert(InvalidEpoch.selector);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
    }

    function test_SettleCDNPaymentRail() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);

        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_1, 1, 2, 300000);

        vm.prank(user1);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_,
            bool isInitialized
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 0);
        assertEq(cacheMissBytesUsed, 1500);
        assertEq(maxReportedEpoch, 2);
        assertEq(lastCDNSettlementEpoch_, 2);
        assertEq(lastCacheMissSettlementEpoch_, 0);
        assertTrue(isInitialized);

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(cdnAmount, 300000);
        assertEq(cacheMissAmount, 0);
    }

    function test_SettleCacheMissPaymentRail() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);

        vm.expectEmit(true, false, false, true);
        emit CacheMissSettlement(DATA_SET_ID_1, 1, 2, 300000);

        vm.prank(user1);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        (
            uint256 cdnBytesUsed,
            uint256 cacheMissBytesUsed,
            uint256 maxReportedEpoch,
            uint256 lastCDNSettlementEpoch_,
            uint256 lastCacheMissSettlementEpoch_,
            bool isInitialized
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 3000);
        assertEq(cacheMissBytesUsed, 0);
        assertEq(maxReportedEpoch, 2);
        assertEq(lastCDNSettlementEpoch_, 0);
        assertEq(lastCacheMissSettlementEpoch_, 2);
        assertTrue(isInitialized);

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
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        vm.expectRevert(NoUsageToSettle.selector);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        vm.expectRevert(NoUsageToSettle.selector);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);
    }

    function test_TerminateCDNPaymentRails() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        vm.expectEmit(true, false, false, false);
        emit PaymentRailsTerminated(DATA_SET_ID_1);

        filBeam.terminateCDNPaymentRails(DATA_SET_ID_1);

        assertTrue(mockFWSS.terminatedDataSets(DATA_SET_ID_1));
    }

    function test_TerminateCDNPaymentRailsRevertOnlyOwner() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        vm.prank(user1);
        vm.expectRevert();
        filBeam.terminateCDNPaymentRails(DATA_SET_ID_1);
    }

    function test_TerminateCDNPaymentRailsRevertDataSetNotInitialized() public {
        vm.expectRevert(DataSetNotInitialized.selector);
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
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_2, 1, 2000, 1000);

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
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1500, 750);
        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        assertEq(mockFWSS.getSettlementsCount(), 2);

        (,, uint256 maxReportedEpoch, uint256 lastCDNSettlementEpoch_, uint256 lastCacheMissSettlementEpoch_,) =
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

        filBeam.reportUsageRollup(dataSetId, epoch, int256(cdnBytes), int256(cacheMissBytes));

        (uint256 cdnBytesUsed, uint256 cacheMissBytesUsed, uint256 maxReportedEpoch,,,) =
            filBeam.getDataSetUsage(dataSetId);

        assertEq(cdnBytesUsed, cdnBytes);
        assertEq(cacheMissBytesUsed, cacheMissBytes);
        assertEq(maxReportedEpoch, epoch);
    }

    function test_ZeroUsageReporting() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 0, 0);
        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 cdnAmount, uint256 cacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(cdnAmount, 0);
        assertEq(cacheMissAmount, 0);
    }

    function test_IndependentSettlement() public {
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 2, 2000, 1000);
        filBeam.reportUsageRollup(DATA_SET_ID_1, 3, 1500, 750);

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);

        (
            ,
            uint256 cacheMissBytesUsed1,
            uint256 maxReportedEpoch1,
            uint256 lastCDNSettlementEpoch1,
            uint256 lastCacheMissSettlementEpoch1,
        ) = filBeam.getDataSetUsage(DATA_SET_ID_1);
        assertEq(cacheMissBytesUsed1, 2250);
        assertEq(maxReportedEpoch1, 3);
        assertEq(lastCDNSettlementEpoch1, 3);
        assertEq(lastCacheMissSettlementEpoch1, 0);

        filBeam.reportUsageRollup(DATA_SET_ID_1, 4, 800, 400);

        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);

        (
            uint256 cdnBytesUsed2,
            uint256 cacheMissBytesUsed2,
            uint256 maxReportedEpoch2,
            uint256 lastCDNSettlementEpoch2,
            uint256 lastCacheMissSettlementEpoch2,
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
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        filBeam.settleCDNPaymentRail(DATA_SET_ID_1);
        (uint256 dataSetId1, uint256 cdnAmount1, uint256 cacheMissAmount1,) = mockFWSS.getSettlement(0);
        assertEq(cdnAmount1, 1000 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount1, 0);

        filBeam.settleCacheMissPaymentRail(DATA_SET_ID_1);
        (uint256 dataSetId2, uint256 cdnAmount2, uint256 cacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(cdnAmount2, 0);
        assertEq(cacheMissAmount2, 500 * CACHE_MISS_RATE_PER_BYTE);
    }

    function test_UpgradeContract() public {
        // Report some usage first
        filBeam.reportUsageRollup(DATA_SET_ID_1, 1, 1000, 500);

        // Create new implementation
        FilBeam newImplementation = new FilBeam();

        // Upgrade to new implementation (only owner can do this)
        filBeam.upgradeToAndCall(address(newImplementation), "");

        // Verify state is preserved after upgrade
        (uint256 cdnBytesUsed, uint256 cacheMissBytesUsed, uint256 maxReportedEpoch,,,) =
            filBeam.getDataSetUsage(DATA_SET_ID_1);

        assertEq(cdnBytesUsed, 1000);
        assertEq(cacheMissBytesUsed, 500);
        assertEq(maxReportedEpoch, 1);
        assertEq(filBeam.owner(), owner);
    }

    function test_UpgradeContractRevertOnlyOwner() public {
        FilBeam newImplementation = new FilBeam();

        vm.prank(user1);
        vm.expectRevert();
        filBeam.upgradeToAndCall(address(newImplementation), "");
    }
}
