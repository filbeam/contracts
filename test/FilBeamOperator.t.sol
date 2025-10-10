// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FilBeamOperator} from "../src/FilBeamOperator.sol";
import {IFWSS} from "../src/interfaces/IFWSS.sol";
import {MockFWSS} from "../src/mocks/MockFWSS.sol";
import {MockPayments} from "../src/mocks/MockPayments.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Errors.sol";

contract FilBeamOperatorTest is Test {
    FilBeamOperator public filBeam;
    MockFWSS public mockFWSS;
    MockPayments public mockPayments;
    address public owner;
    address public filBeamOperatorController;
    address public user1;
    address public user2;

    uint256 constant DATA_SET_ID_1 = 1;
    uint256 constant DATA_SET_ID_2 = 2;
    uint256 constant CDN_RATE_PER_BYTE = 100;
    uint256 constant CACHE_MISS_RATE_PER_BYTE = 200;

    event UsageReported(
        uint256 indexed dataSetId, uint256 indexed epoch, uint256 cdnBytesUsed, uint256 cacheMissBytesUsed
    );

    event CDNSettlement(uint256 indexed dataSetId, uint256 cdnAmount);

    event CacheMissSettlement(uint256 indexed dataSetId, uint256 cacheMissAmount);

    event PaymentRailsTerminated(uint256 indexed dataSetId);

    event FilBeamControllerUpdated(address indexed oldController, address indexed newController);

    function setUp() public {
        owner = address(this);
        filBeamOperatorController = makeAddr("filBeamOperatorController");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        mockFWSS = new MockFWSS();
        mockPayments = new MockPayments();

        // Deploy FilBeamOperator contract (deployer becomes owner)
        filBeam = new FilBeamOperator(
            address(mockFWSS),
            address(mockPayments),
            CDN_RATE_PER_BYTE,
            CACHE_MISS_RATE_PER_BYTE,
            filBeamOperatorController
        );

        mockFWSS.setAuthorizedCaller(address(filBeam));

        // Set up default rails for testing
        _setupDefaultRails();
    }

    function _setupDefaultRails() internal {
        // Set up CDN rail for DATA_SET_ID_1
        MockPayments.RailView memory cdnRail = MockPayments.RailView({
            token: IERC20(address(0)),
            from: user1,
            to: user2,
            operator: address(0),
            validator: address(0),
            paymentRate: 100,
            lockupPeriod: 100,
            lockupFixed: 1000000, // 1M default lockup
            settledUpTo: 0,
            endEpoch: 0,
            commissionRateBps: 0,
            serviceFeeRecipient: address(0)
        });
        mockPayments.setRail(1, cdnRail);

        // Set up cache miss rail for DATA_SET_ID_1
        MockPayments.RailView memory cacheMissRail = MockPayments.RailView({
            token: IERC20(address(0)),
            from: user1,
            to: user2,
            operator: address(0),
            validator: address(0),
            paymentRate: 200,
            lockupPeriod: 100,
            lockupFixed: 1000000, // 1M default lockup
            settledUpTo: 0,
            endEpoch: 0,
            commissionRateBps: 0,
            serviceFeeRecipient: address(0)
        });
        mockPayments.setRail(2, cacheMissRail);

        // Set up CDN rail for DATA_SET_ID_2
        MockPayments.RailView memory cdnRail2 = MockPayments.RailView({
            token: IERC20(address(0)),
            from: user1,
            to: user2,
            operator: address(0),
            validator: address(0),
            paymentRate: 100,
            lockupPeriod: 100,
            lockupFixed: 1000000, // 1M default lockup
            settledUpTo: 0,
            endEpoch: 0,
            commissionRateBps: 0,
            serviceFeeRecipient: address(0)
        });
        mockPayments.setRail(3, cdnRail2);

        // Set up cache miss rail for DATA_SET_ID_2
        MockPayments.RailView memory cacheMissRail2 = MockPayments.RailView({
            token: IERC20(address(0)),
            from: user1,
            to: user2,
            operator: address(0),
            validator: address(0),
            paymentRate: 200,
            lockupPeriod: 100,
            lockupFixed: 1000000, // 1M default lockup
            settledUpTo: 0,
            endEpoch: 0,
            commissionRateBps: 0,
            serviceFeeRecipient: address(0)
        });
        mockPayments.setRail(4, cacheMissRail2);

        // Set up DataSetInfo for DATA_SET_ID_1
        IFWSS.DataSetInfo memory dsInfo = IFWSS.DataSetInfo({
            pdpRailId: 0,
            cacheMissRailId: 2,
            cdnRailId: 1,
            payer: user1,
            payee: user2,
            serviceProvider: address(0),
            commissionBps: 0,
            clientDataSetId: 0,
            pdpEndEpoch: 0,
            providerId: 0
        });
        mockFWSS.setDataSetInfo(DATA_SET_ID_1, dsInfo);

        // Set up DataSetInfo for DATA_SET_ID_2
        IFWSS.DataSetInfo memory dsInfo2 = IFWSS.DataSetInfo({
            pdpRailId: 0,
            cacheMissRailId: 4,
            cdnRailId: 3,
            payer: user1,
            payee: user2,
            serviceProvider: address(0),
            commissionBps: 0,
            clientDataSetId: 0,
            pdpEndEpoch: 0,
            providerId: 0
        });
        mockFWSS.setDataSetInfo(DATA_SET_ID_2, dsInfo2);
    }

    // Helper functions to create single-element arrays
    function _singleUint256Array(uint256 value) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = value;
        return arr;
    }

    function test_Initialize() public view {
        assertEq(address(filBeam.fwss()), address(mockFWSS));
        assertEq(address(filBeam.payments()), address(mockPayments));
        assertEq(filBeam.owner(), owner);
        assertEq(filBeam.filBeamOperatorController(), filBeamOperatorController);
        assertEq(filBeam.cdnRatePerByte(), CDN_RATE_PER_BYTE);
        assertEq(filBeam.cacheMissRatePerByte(), CACHE_MISS_RATE_PER_BYTE);
    }

    function test_InitializeRevertZeroAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        new FilBeamOperator(
            address(0), address(mockPayments), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, filBeamOperatorController
        );

        vm.expectRevert(InvalidAddress.selector);
        new FilBeamOperator(
            address(mockFWSS), address(0), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, filBeamOperatorController
        );
    }

    function test_InitializeRevertZeroRate() public {
        vm.expectRevert(InvalidRate.selector);
        new FilBeamOperator(
            address(mockFWSS), address(mockPayments), 0, CACHE_MISS_RATE_PER_BYTE, filBeamOperatorController
        );

        vm.expectRevert(InvalidRate.selector);
        new FilBeamOperator(address(mockFWSS), address(mockPayments), CDN_RATE_PER_BYTE, 0, filBeamOperatorController);
    }

    function test_InitializeRevertZeroFilBeamController() public {
        vm.expectRevert(InvalidAddress.selector);
        new FilBeamOperator(
            address(mockFWSS), address(mockPayments), CDN_RATE_PER_BYTE, CACHE_MISS_RATE_PER_BYTE, address(0)
        );
    }

    function test_ReportUsageRollup() public {
        vm.expectEmit(true, true, false, true);
        emit UsageReported(DATA_SET_ID_1, 1, 1000, 500);

        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        (uint256 cdnAmount, uint256 cacheMissAmount, uint256 maxReportedEpoch) = filBeam.dataSetUsage(DATA_SET_ID_1);

        assertEq(cdnAmount, 1000 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount, 500 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxReportedEpoch, 1);
    }

    function test_ReportUsageRollupMultipleEpochs() public {
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(3),
            _singleUint256Array(1500),
            _singleUint256Array(750)
        );
        vm.stopPrank();

        (uint256 cdnAmount, uint256 cacheMissAmount, uint256 maxReportedEpoch) = filBeam.dataSetUsage(DATA_SET_ID_1);

        assertEq(cdnAmount, 4500 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount, 2250 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxReportedEpoch, 3);
    }

    function test_ReportUsageRollupRevertUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(Unauthorized.selector);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
    }

    function test_ReportUsageRollupRevertZeroEpoch() public {
        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(0),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
    }

    function test_ReportUsageRollupRevertDuplicateEpoch() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
    }

    function test_ReportUsageRollupRevertInvalidEpochOrder() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(3),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
    }

    function test_SettleCDNPaymentRail() public {
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_1, 300000);

        vm.prank(user1);
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        (uint256 cdnAmount, uint256 cacheMissAmount, uint256 maxReportedEpoch) = filBeam.dataSetUsage(DATA_SET_ID_1);

        assertEq(cdnAmount, 0);
        assertEq(cacheMissAmount, 1500 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxReportedEpoch, 2);

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 settledCdnAmount, uint256 settledCacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(settledCdnAmount, 300000);
        assertEq(settledCacheMissAmount, 0);
    }

    function test_SettleCacheMissPaymentRail() public {
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit CacheMissSettlement(DATA_SET_ID_1, 300000);

        vm.prank(user1);
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        (uint256 cdnAmount, uint256 cacheMissAmount, uint256 maxReportedEpoch) = filBeam.dataSetUsage(DATA_SET_ID_1);

        assertEq(cdnAmount, 3000 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount, 0);
        assertEq(maxReportedEpoch, 2);

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 settledCdnAmount, uint256 settledCacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(settledCdnAmount, 0);
        assertEq(settledCacheMissAmount, 300000);
    }

    function test_SettlementDataSetNotInitialized() public {
        // Should not revert, just return early without emitting events
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // Verify no settlements were made
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SettlementNoUsageToSettle() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 1);

        // Should not revert, just return early without additional settlements
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 1); // Still 1, no new settlement

        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 2);

        // Should not revert, just return early without additional settlements
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 2); // Still 2, no new settlement
    }

    function test_TerminateCDNPaymentRails() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        vm.expectEmit(true, false, false, false);
        emit PaymentRailsTerminated(DATA_SET_ID_1);

        vm.prank(filBeamOperatorController);
        filBeam.terminateCDNPaymentRails(DATA_SET_ID_1);

        assertTrue(mockFWSS.terminatedDataSets(DATA_SET_ID_1));
    }

    function test_TerminateCDNPaymentRailsRevertUnauthorized() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

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
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_2),
            _singleUint256Array(1),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        vm.stopPrank();

        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_2));

        assertEq(mockFWSS.getSettlementsCount(), 2);

        (uint256 settledDataSetId1, uint256 settledCdnAmount1, uint256 settledCacheMissAmount1,) =
            mockFWSS.getSettlement(0);
        assertEq(settledDataSetId1, DATA_SET_ID_1);
        assertEq(settledCdnAmount1, 100000);
        assertEq(settledCacheMissAmount1, 0);

        (uint256 settledDataSetId2, uint256 settledCdnAmount2, uint256 settledCacheMissAmount2,) =
            mockFWSS.getSettlement(1);
        assertEq(settledDataSetId2, DATA_SET_ID_2);
        assertEq(settledCdnAmount2, 0);
        assertEq(settledCacheMissAmount2, 200000);
    }

    function test_PartialSettlement() public {
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        vm.stopPrank();
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(3),
            _singleUint256Array(1500),
            _singleUint256Array(750)
        );
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        assertEq(mockFWSS.getSettlementsCount(), 2);

        (,, uint256 maxReportedEpoch) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(maxReportedEpoch, 3);
    }

    function testFuzz_ReportUsageRollup(uint256 dataSetId, uint256 epoch, uint256 cdnBytes, uint256 cacheMissBytes)
        public
    {
        vm.assume(dataSetId != 0);
        vm.assume(epoch > 0 && epoch < type(uint256).max);
        vm.assume(cdnBytes < type(uint256).max / CDN_RATE_PER_BYTE);
        vm.assume(cacheMissBytes < type(uint256).max / CACHE_MISS_RATE_PER_BYTE);

        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(dataSetId),
            _singleUint256Array(epoch),
            _singleUint256Array(cdnBytes),
            _singleUint256Array(cacheMissBytes)
        );

        (uint256 cdnAmount, uint256 cacheMissAmount, uint256 maxReportedEpoch) = filBeam.dataSetUsage(dataSetId);

        assertEq(cdnAmount, cdnBytes * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount, cacheMissBytes * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxReportedEpoch, epoch);
    }

    function test_ZeroUsageReporting() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1), _singleUint256Array(1), _singleUint256Array(0), _singleUint256Array(0)
        );

        // Should not emit event when amount is 0 (early return)
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // No external call should be made when amount is 0
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_IndependentSettlement() public {
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(3),
            _singleUint256Array(1500),
            _singleUint256Array(750)
        );
        vm.stopPrank();

        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        (, uint256 cacheMissAmount1, uint256 maxReportedEpoch1) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cacheMissAmount1, 2250 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxReportedEpoch1, 3);

        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(4),
            _singleUint256Array(800),
            _singleUint256Array(400)
        );

        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        (uint256 cdnAmount2, uint256 cacheMissAmount2, uint256 maxReportedEpoch2) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount2, 800 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount2, 0);
        assertEq(maxReportedEpoch2, 4);

        assertEq(mockFWSS.getSettlementsCount(), 2);

        (uint256 settledDataSetId1, uint256 settledCdnAmount1, uint256 settledCacheMissAmount1,) =
            mockFWSS.getSettlement(0);
        assertEq(settledDataSetId1, DATA_SET_ID_1);
        assertEq(settledCdnAmount1, 450000);
        assertEq(settledCacheMissAmount1, 0);

        (uint256 settledDataSetId2, uint256 settledCdnAmount2, uint256 settledCacheMissAmount2,) =
            mockFWSS.getSettlement(1);
        assertEq(settledDataSetId2, DATA_SET_ID_1);
        assertEq(settledCdnAmount2, 0);
        assertEq(settledCacheMissAmount2, 530000);
    }

    function test_RateCalculations() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        (, uint256 settledCdnAmount1, uint256 settledCacheMissAmount1,) = mockFWSS.getSettlement(0);
        assertEq(settledCdnAmount1, 1000 * CDN_RATE_PER_BYTE);
        assertEq(settledCacheMissAmount1, 0);

        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        (, uint256 settledCdnAmount2, uint256 settledCacheMissAmount2,) = mockFWSS.getSettlement(1);
        assertEq(settledCdnAmount2, 0);
        assertEq(settledCacheMissAmount2, 500 * CACHE_MISS_RATE_PER_BYTE);
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

        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);

        (uint256 cdnAmount1, uint256 cacheMissAmount1, uint256 maxEpoch1) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount1, 3000 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount1, 1500 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxEpoch1, 2);

        (uint256 cdnAmount2, uint256 cacheMissAmount2, uint256 maxEpoch2) = filBeam.dataSetUsage(DATA_SET_ID_2);
        assertEq(cdnAmount2, 1500 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount2, 750 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxEpoch2, 1);
    }

    function test_ReportUsageRollupBatchRevertArrayLengthMismatch() public {
        uint256[] memory dataSetIds = new uint256[](2);
        uint256[] memory epochs = new uint256[](3);
        uint256[] memory cdnBytesUsed = new uint256[](2);
        uint256[] memory cacheMissBytesUsed = new uint256[](2);

        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidUsageAmount.selector);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
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
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
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

        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchRevertDuplicateEpoch() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        uint256[] memory dataSetIds = new uint256[](1);
        uint256[] memory epochs = new uint256[](1);
        uint256[] memory cdnBytesUsed = new uint256[](1);
        uint256[] memory cacheMissBytesUsed = new uint256[](1);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 1;
        cdnBytesUsed[0] = 2000;
        cacheMissBytesUsed[0] = 1000;

        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchRevertInvalidEpochOrder() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(3),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        uint256[] memory dataSetIds = new uint256[](1);
        uint256[] memory epochs = new uint256[](1);
        uint256[] memory cdnBytesUsed = new uint256[](1);
        uint256[] memory cacheMissBytesUsed = new uint256[](1);

        dataSetIds[0] = DATA_SET_ID_1;
        epochs[0] = 2;
        cdnBytesUsed[0] = 2000;
        cacheMissBytesUsed[0] = 1000;

        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
    }

    function test_ReportUsageRollupBatchEmptyArrays() public {
        uint256[] memory dataSetIds = new uint256[](0);
        uint256[] memory epochs = new uint256[](0);
        uint256[] memory cdnBytesUsed = new uint256[](0);
        uint256[] memory cacheMissBytesUsed = new uint256[](0);

        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);
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

        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);

        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        assertEq(mockFWSS.getSettlementsCount(), 1);
        (uint256 dataSetId, uint256 settledCdnAmount, uint256 settledCacheMissAmount,) = mockFWSS.getSettlement(0);
        assertEq(dataSetId, DATA_SET_ID_1);
        assertEq(settledCdnAmount, 300000);
        assertEq(settledCacheMissAmount, 0);
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

        vm.prank(filBeamOperatorController);
        vm.expectRevert(InvalidEpoch.selector);
        filBeam.recordUsageRollups(dataSetIds, epochs, cdnBytesUsed, cacheMissBytesUsed);

        (uint256 cdnAmount1, uint256 cacheMissAmount1, uint256 maxReportedEpoch1) = filBeam.dataSetUsage(DATA_SET_ID_1);

        assertEq(cdnAmount1, 0);
        assertEq(cacheMissAmount1, 0);
        assertEq(maxReportedEpoch1, 0);
    }

    function test_SettleCDNPaymentRailBatch() public {
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_2),
            _singleUint256Array(1),
            _singleUint256Array(1500),
            _singleUint256Array(750)
        );
        vm.stopPrank();

        uint256[] memory dataSetIds = new uint256[](2);
        dataSetIds[0] = DATA_SET_ID_1;
        dataSetIds[1] = DATA_SET_ID_2;

        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_1, 300000);
        vm.expectEmit(true, false, false, true);
        emit CDNSettlement(DATA_SET_ID_2, 150000);

        vm.prank(user1);
        filBeam.settleCDNPaymentRails(dataSetIds);

        (uint256 cdnAmount1, uint256 cacheMissAmount1, uint256 maxEpoch1) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount1, 0);
        assertEq(cacheMissAmount1, 1500 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxEpoch1, 2);

        (uint256 cdnAmount2, uint256 cacheMissAmount2, uint256 maxEpoch2) = filBeam.dataSetUsage(DATA_SET_ID_2);
        assertEq(cdnAmount2, 0);
        assertEq(cacheMissAmount2, 750 * CACHE_MISS_RATE_PER_BYTE);
        assertEq(maxEpoch2, 1);

        assertEq(mockFWSS.getSettlementsCount(), 2);
        (uint256 settledDataSetId1, uint256 settledCdnAmount1, uint256 settledCacheMissAmount1,) =
            mockFWSS.getSettlement(0);
        assertEq(settledDataSetId1, DATA_SET_ID_1);
        assertEq(settledCdnAmount1, 300000);
        assertEq(settledCacheMissAmount1, 0);

        (uint256 settledDataSetId2, uint256 settledCdnAmount2, uint256 settledCacheMissAmount2,) =
            mockFWSS.getSettlement(1);
        assertEq(settledDataSetId2, DATA_SET_ID_2);
        assertEq(settledCdnAmount2, 150000);
        assertEq(settledCacheMissAmount2, 0);
    }

    function test_SettleCacheMissPaymentRailBatch() public {
        vm.startPrank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(2000),
            _singleUint256Array(1000)
        );
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_2),
            _singleUint256Array(1),
            _singleUint256Array(1500),
            _singleUint256Array(750)
        );
        vm.stopPrank();

        uint256[] memory dataSetIds = new uint256[](2);
        dataSetIds[0] = DATA_SET_ID_1;
        dataSetIds[1] = DATA_SET_ID_2;

        vm.expectEmit(true, false, false, true);
        emit CacheMissSettlement(DATA_SET_ID_1, 300000);
        vm.expectEmit(true, false, false, true);
        emit CacheMissSettlement(DATA_SET_ID_2, 150000);

        vm.prank(user1);
        filBeam.settleCacheMissPaymentRails(dataSetIds);

        (uint256 cdnAmount1, uint256 cacheMissAmount1, uint256 maxEpoch1) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount1, 3000 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount1, 0);
        assertEq(maxEpoch1, 2);

        (uint256 cdnAmount2, uint256 cacheMissAmount2, uint256 maxEpoch2) = filBeam.dataSetUsage(DATA_SET_ID_2);
        assertEq(cdnAmount2, 1500 * CDN_RATE_PER_BYTE);
        assertEq(cacheMissAmount2, 0);
        assertEq(maxEpoch2, 1);

        assertEq(mockFWSS.getSettlementsCount(), 2);
        (uint256 settledDataSetId1, uint256 settledCdnAmount1, uint256 settledCacheMissAmount1,) =
            mockFWSS.getSettlement(0);
        assertEq(settledDataSetId1, DATA_SET_ID_1);
        assertEq(settledCdnAmount1, 0);
        assertEq(settledCacheMissAmount1, 300000);

        (uint256 settledDataSetId2, uint256 settledCdnAmount2, uint256 settledCacheMissAmount2,) =
            mockFWSS.getSettlement(1);
        assertEq(settledDataSetId2, DATA_SET_ID_2);
        assertEq(settledCdnAmount2, 0);
        assertEq(settledCacheMissAmount2, 150000);
    }

    function test_SettleCDNPaymentRailBatchEmptyArray() public {
        uint256[] memory dataSetIds = new uint256[](0);
        filBeam.settleCDNPaymentRails(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SettleCacheMissPaymentRailBatchEmptyArray() public {
        uint256[] memory dataSetIds = new uint256[](0);
        filBeam.settleCacheMissPaymentRails(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SettleCDNPaymentRailBatchDataSetNotInitialized() public {
        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        // Should not revert, just return early without settlements
        filBeam.settleCDNPaymentRails(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SettleCacheMissPaymentRailBatchDataSetNotInitialized() public {
        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        // Should not revert, just return early without settlements
        filBeam.settleCacheMissPaymentRails(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 0);
    }

    function test_SettleCDNPaymentRailBatchNoUsageToSettle() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 1);

        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        // Should not revert, just return early without new settlements
        filBeam.settleCDNPaymentRails(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 1); // Still 1, no new settlement
    }

    function test_SettleCacheMissPaymentRailBatchNoUsageToSettle() public {
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 1);

        uint256[] memory dataSetIds = new uint256[](1);
        dataSetIds[0] = DATA_SET_ID_1;

        // Should not revert, just return early without new settlements
        filBeam.settleCacheMissPaymentRails(dataSetIds);
        assertEq(mockFWSS.getSettlementsCount(), 1); // Still 1, no new settlement
    }

    function test_SilentEarlyReturnsNoEvents() public {
        // Test 1: Uninitialized dataset should not revert or change state
        uint256 initialSettlementCount = mockFWSS.getSettlementsCount();
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), initialSettlementCount, "Should not settle uninitialized dataset");

        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), initialSettlementCount, "Should not settle uninitialized dataset");

        // Initialize with usage
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        // Settle once (should work)
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), initialSettlementCount + 1, "Should settle first time");

        // Test 2: Already settled dataset should not create new settlements
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), initialSettlementCount + 1, "Should not settle when no new usage");
    }

    function test_SettlementBatchMixedInitialization() public {
        // Record usage for DATA_SET_ID_1 but not DATA_SET_ID_2
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        uint256[] memory dataSetIds = new uint256[](2);
        dataSetIds[0] = DATA_SET_ID_1;
        dataSetIds[1] = DATA_SET_ID_2; // Not initialized

        // Should settle DATA_SET_ID_1 and skip DATA_SET_ID_2 without reverting
        filBeam.settleCDNPaymentRails(dataSetIds);

        // Verify DATA_SET_ID_1 was settled
        (uint256 cdnAmount1, uint256 cacheMissAmount1, uint256 maxEpoch1) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount1, 0); // Settled, so amount is 0
        assertEq(cacheMissAmount1, 500 * CACHE_MISS_RATE_PER_BYTE); // Not settled yet
        assertEq(maxEpoch1, 1);

        assertEq(mockFWSS.getSettlementsCount(), 1); // Only DATA_SET_ID_1 was settled
    }

    function test_SetFilBeamController() public {
        address newController = makeAddr("newController");

        vm.expectEmit(true, true, false, true);
        emit FilBeamControllerUpdated(filBeamOperatorController, newController);

        filBeam.setFilBeamOperatorController(newController);

        assertEq(filBeam.filBeamOperatorController(), newController);
    }

    function test_SetFilBeamControllerRevertUnauthorized() public {
        address newController = makeAddr("newController");

        vm.prank(user1);
        vm.expectRevert();
        filBeam.setFilBeamOperatorController(newController);
    }

    function test_SetFilBeamControllerRevertZeroAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        filBeam.setFilBeamOperatorController(address(0));
    }

    function test_SetFilBeamControllerUpdatesAccess() public {
        address newController = makeAddr("newController");

        filBeam.setFilBeamOperatorController(newController);

        vm.prank(filBeamOperatorController);
        vm.expectRevert(Unauthorized.selector);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        vm.prank(newController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        (uint256 cdnAmount,,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount, 1000 * CDN_RATE_PER_BYTE);
    }

    // Test settling accumulated amounts without new usage
    function test_SettleAccumulatedAmountWithoutNewUsage() public {
        // Simulate partial settlement by manually setting accumulated amount
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(2000), // 200k amount
            _singleUint256Array(1500) // 300k amount
        );

        // First settlement
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // Verify initial settlements
        assertEq(mockFWSS.getSettlementsCount(), 2);

        // Manually add accumulated amounts (simulating partial settlement scenario)
        // This would happen if the previous settlement was limited by lockupFixed
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(1000), // Add 100k CDN amount
            _singleUint256Array(500) // Add 100k cache miss amount
        );

        // Settle CDN without new usage report
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // Verify CDN was settled
        assertEq(mockFWSS.getSettlementsCount(), 3);
        (uint256 cdnAmount,,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount, 0, "CDN amount should be fully settled");

        // Settle cache miss without new usage report
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // Verify cache miss was settled
        assertEq(mockFWSS.getSettlementsCount(), 4);
        (, uint256 cacheMissAmount,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cacheMissAmount, 0, "Cache miss amount should be fully settled");
    }

    function test_SettlementWithNoRailConfigured() public {
        // Set up DATA_SET_ID_2 with no rails
        IFWSS.DataSetInfo memory dsInfo = IFWSS.DataSetInfo({
            pdpRailId: 0,
            cacheMissRailId: 0,
            cdnRailId: 0,
            payer: user1,
            payee: user2,
            serviceProvider: address(0),
            commissionBps: 0,
            clientDataSetId: 0,
            pdpEndEpoch: 0,
            providerId: 0
        });
        mockFWSS.setDataSetInfo(DATA_SET_ID_2, dsInfo);

        // Record usage
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_2),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        // Try to settle - should not revert or settle
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_2));
        assertEq(mockFWSS.getSettlementsCount(), 0, "Should not settle without rail");

        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_2));
        assertEq(mockFWSS.getSettlementsCount(), 0, "Should not settle without rail");

        // Amount should still be accumulated
        (uint256 cdnAmount, uint256 cacheMissAmount,) = filBeam.dataSetUsage(DATA_SET_ID_2);
        assertEq(cdnAmount, 100000, "Amount should still be accumulated");
        assertEq(cacheMissAmount, 100000, "Amount should still be accumulated");
    }

    // Test partial settlement when lockup is less than accumulated amount
    function test_PartialSettlementWithLimitedLockup() public {
        // Set limited lockup for CDN rail (less than what will be accumulated)
        mockPayments.setLockupFixed(1, 50000); // CDN rail has 50k lockup
        mockPayments.setLockupFixed(2, 30000); // Cache miss rail has 30k lockup

        // Record usage that will exceed the lockup limits
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000), // 100k CDN amount (1000 * 100)
            _singleUint256Array(500) // 100k cache miss amount (500 * 200)
        );

        // Check accumulated amounts
        (uint256 cdnAmount1, uint256 cacheMissAmount1,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount1, 100000, "Should have 100k CDN amount");
        assertEq(cacheMissAmount1, 100000, "Should have 100k cache miss amount");

        // First CDN settlement - should only settle 50k due to lockup limit
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // Check remaining amount after partial settlement
        (uint256 cdnAmount2, uint256 cacheMissAmount2,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount2, 50000, "Should have 50k CDN remaining after partial settlement");
        assertEq(cacheMissAmount2, 100000, "Cache miss amount should be unchanged");

        // Verify settlement amount
        assertEq(mockFWSS.getSettlementsCount(), 1);
        (, uint256 settledCdn1,,) = mockFWSS.getSettlement(0);
        assertEq(settledCdn1, 50000, "Should have settled 50k CDN");

        // First cache miss settlement - should only settle 30k due to lockup limit
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // Check remaining amount after partial settlement
        (uint256 cdnAmount3, uint256 cacheMissAmount3,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount3, 50000, "CDN amount should be unchanged");
        assertEq(cacheMissAmount3, 70000, "Should have 70k cache miss remaining after partial settlement");

        // Verify settlement amount
        assertEq(mockFWSS.getSettlementsCount(), 2);
        (,, uint256 settledCacheMiss1,) = mockFWSS.getSettlement(1);
        assertEq(settledCacheMiss1, 30000, "Should have settled 30k cache miss");

        // Second CDN settlement - should settle remaining 50k
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        (uint256 cdnAmount4,,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount4, 0, "Should have no CDN remaining after second settlement");

        assertEq(mockFWSS.getSettlementsCount(), 3);
        (, uint256 settledCdn2,,) = mockFWSS.getSettlement(2);
        assertEq(settledCdn2, 50000, "Should have settled remaining 50k CDN");

        // Increase lockup and settle remaining cache miss
        mockPayments.setLockupFixed(2, 100000); // Increase cache miss rail lockup
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        (, uint256 cacheMissAmount4,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cacheMissAmount4, 0, "Should have no cache miss remaining");

        assertEq(mockFWSS.getSettlementsCount(), 4);
        (,, uint256 settledCacheMiss2,) = mockFWSS.getSettlement(3);
        assertEq(settledCacheMiss2, 70000, "Should have settled remaining 70k cache miss");
    }

    function test_SettlementWithZeroLockup() public {
        // Set lockup to 0
        mockPayments.setLockupFixed(1, 0);

        // Record usage
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        // Try to settle - should not settle anything due to zero lockup
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 0, "Should not settle with zero lockup");

        // Amount should still be accumulated
        (uint256 cdnAmount,,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount, 100000, "Amount should still be accumulated");
    }

    function test_SettlementWithInactiveRail() public {
        // Record usage first
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(1000),
            _singleUint256Array(500)
        );

        // Make rail inactive by removing it
        mockPayments.setRailExists(1, false);

        // Try to settle - should revert due to inactive rail
        vm.expectRevert("Rail does not exist");
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        // Amount should still be accumulated
        (uint256 cdnAmount,,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount, 100000, "Amount should still be accumulated");

        // Reactivate rail and verify settlement works
        mockPayments.setRailExists(1, true);
        mockPayments.setLockupFixed(1, 100000);

        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 1, "Should settle after reactivation");

        (uint256 cdnAmountAfter,,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmountAfter, 0, "Amount should be settled");
    }

    // Test multiple partial settlements without new usage
    function test_MultiplePartialSettlementsWithoutNewUsage() public {
        // Record initial usage
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(1),
            _singleUint256Array(5000), // 500k CDN amount
            _singleUint256Array(2500) // 500k cache miss amount
        );

        // First settlement - settles all accumulated amounts
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));

        assertEq(mockFWSS.getSettlementsCount(), 2);
        (uint256 cdnAmount1, uint256 cacheMissAmount1,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount1, 0, "CDN amount should be 0 after first settlement");
        assertEq(cacheMissAmount1, 0, "Cache miss amount should be 0 after first settlement");

        // Simulate accumulated amounts from a partial settlement
        // (In real scenario, this could happen if external contract limits settlement)
        // We'll add more usage to simulate accumulation
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(DATA_SET_ID_1),
            _singleUint256Array(2),
            _singleUint256Array(3000), // 300k CDN amount
            _singleUint256Array(1500) // 300k cache miss amount
        );

        // Second settlement - should settle new amounts
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 3);

        // Try to settle CDN again without new usage - should not create new settlement
        uint256 settlementCountBefore = mockFWSS.getSettlementsCount();
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), settlementCountBefore, "Should not settle when no amount");

        // Settle cache miss
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), 4);

        // Verify final state
        (uint256 cdnAmount2, uint256 cacheMissAmount2,) = filBeam.dataSetUsage(DATA_SET_ID_1);
        assertEq(cdnAmount2, 0, "CDN amount should be 0 after all settlements");
        assertEq(cacheMissAmount2, 0, "Cache miss amount should be 0 after all settlements");

        // Try settling again - should not create new settlements
        uint256 finalCount = mockFWSS.getSettlementsCount();
        filBeam.settleCDNPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(DATA_SET_ID_1));
        assertEq(mockFWSS.getSettlementsCount(), finalCount, "No new settlements when no amount");
    }

    // Test settlement with rail ID 0 (no rail configured)
    function test_SettlementWithNoRailId() public {
        // Create a data set with no rails (rail IDs = 0)
        IFWSS.DataSetInfo memory dsInfo = IFWSS.DataSetInfo({
            pdpRailId: 0,
            cacheMissRailId: 0,
            cdnRailId: 0,
            payer: user1,
            payee: user2,
            serviceProvider: address(0),
            commissionBps: 0,
            clientDataSetId: 0,
            pdpEndEpoch: 0,
            providerId: 0
        });
        uint256 dataSetId3 = 3;
        mockFWSS.setDataSetInfo(dataSetId3, dsInfo);

        // Record usage
        vm.prank(filBeamOperatorController);
        filBeam.recordUsageRollups(
            _singleUint256Array(dataSetId3), _singleUint256Array(1), _singleUint256Array(1000), _singleUint256Array(500)
        );

        // Try to settle - should not revert or settle
        uint256 settlementCountBefore = mockFWSS.getSettlementsCount();
        filBeam.settleCDNPaymentRails(_singleUint256Array(dataSetId3));
        filBeam.settleCacheMissPaymentRails(_singleUint256Array(dataSetId3));
        assertEq(mockFWSS.getSettlementsCount(), settlementCountBefore, "Should not settle with rail ID 0");

        // Amount should still be accumulated
        (uint256 cdnAmount, uint256 cacheMissAmount,) = filBeam.dataSetUsage(dataSetId3);
        assertEq(cdnAmount, 100000, "CDN amount should still be accumulated");
        assertEq(cacheMissAmount, 100000, "Cache miss amount should still be accumulated");
    }
}
