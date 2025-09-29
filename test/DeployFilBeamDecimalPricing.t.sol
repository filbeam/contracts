// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "../script/DeployFilBeam.s.sol";

// Test contract that exposes the internal function
contract TestableDeployFilBeam is DeployFilBeam {
    function calculateUsdfcPerBytePublic(uint256 usdPerTibScaled, uint8 priceDecimals, uint8 tokenDecimals)
        public
        pure
        returns (uint256)
    {
        return calculateUsdfcPerByte(usdPerTibScaled, priceDecimals, tokenDecimals);
    }
}

contract DeployFilBeamDecimalPricingTest is Test {
    TestableDeployFilBeam deployer;

    uint256 constant BYTES_PER_TIB = 1024 * 1024 * 1024 * 1024; // 1 TiB in bytes

    function setUp() public {
        deployer = new TestableDeployFilBeam();
    }

    function test_calculateUsdfcPerByte_WholeNumbers() public view {
        // Test with whole numbers (backward compatibility)
        uint256 usdPerTibScaled = 10; // $10/TiB
        uint8 priceDecimals = 0; // No decimal places
        uint8 tokenDecimals = 6; // USDFC has 6 decimals

        uint256 expected = (10 * (10 ** 6)) / BYTES_PER_TIB; // 10 * 10^6 / 2^40
        uint256 result = deployer.calculateUsdfcPerBytePublic(usdPerTibScaled, priceDecimals, tokenDecimals);

        assertEq(result, expected);
    }

    function test_calculateUsdfcPerByte_TwoDecimals() public view {
        // Test with 2 decimal places
        uint256 usdPerTibScaled = 1250; // $12.50/TiB (1250 with 2 decimals)
        uint8 priceDecimals = 2;
        uint8 tokenDecimals = 6; // USDFC has 6 decimals

        // Expected: (1250 * 10^6) / 10^2 / 2^40 = (12.50 * 10^6) / 2^40
        uint256 expected = (1250 * (10 ** 6)) / (10 ** 2) / BYTES_PER_TIB;
        uint256 result = deployer.calculateUsdfcPerBytePublic(usdPerTibScaled, priceDecimals, tokenDecimals);

        assertEq(result, expected);
    }

    function test_calculateUsdfcPerByte_ThreeDecimals() public view {
        // Test with 3 decimal places
        uint256 usdPerTibScaled = 12750; // $12.750/TiB (12750 with 3 decimals)
        uint8 priceDecimals = 3;
        uint8 tokenDecimals = 6; // USDFC has 6 decimals

        // Expected: (12750 * 10^6) / 10^3 / 2^40 = (12.750 * 10^6) / 2^40
        uint256 expected = (12750 * (10 ** 6)) / (10 ** 3) / BYTES_PER_TIB;
        uint256 result = deployer.calculateUsdfcPerBytePublic(usdPerTibScaled, priceDecimals, tokenDecimals);

        assertEq(result, expected);
    }

    function test_calculateUsdfcPerByte_HighPrecision() public view {
        // Test with high precision pricing
        uint256 usdPerTibScaled = 999999; // $9.99999/TiB (999999 with 5 decimals)
        uint8 priceDecimals = 5;
        uint8 tokenDecimals = 18; // Test with 18 decimal token

        uint256 expected = (999999 * (10 ** 18)) / (10 ** 5) / BYTES_PER_TIB;
        uint256 result = deployer.calculateUsdfcPerBytePublic(usdPerTibScaled, priceDecimals, tokenDecimals);

        assertEq(result, expected);
    }

    function test_calculateUsdfcPerByte_LowPriceHighDecimals() public view {
        // Test edge case: very low price with high decimals
        uint256 usdPerTibScaled = 1; // $0.01/TiB (1 with 2 decimals)
        uint8 priceDecimals = 2;
        uint8 tokenDecimals = 6;

        uint256 expected = (1 * (10 ** 6)) / (10 ** 2) / BYTES_PER_TIB;
        uint256 result = deployer.calculateUsdfcPerBytePublic(usdPerTibScaled, priceDecimals, tokenDecimals);

        assertEq(result, expected);
    }

    function test_calculateUsdfcPerByte_ZeroDecimals() public view {
        // Test with zero decimals (same as whole numbers)
        uint256 usdPerTibScaled = 15; // $15/TiB
        uint8 priceDecimals = 0;
        uint8 tokenDecimals = 6;

        uint256 expected = (15 * (10 ** 6)) / BYTES_PER_TIB;
        uint256 result = deployer.calculateUsdfcPerBytePublic(usdPerTibScaled, priceDecimals, tokenDecimals);

        assertEq(result, expected);
    }

    function test_calculateUsdfcPerByte_CommonDecimalValues() public view {
        // Test common decimal values
        uint8 tokenDecimals = 6;

        // Test $12.50
        uint256 result1 = deployer.calculateUsdfcPerBytePublic(1250, 2, tokenDecimals);
        uint256 expected1 = (1250 * (10 ** tokenDecimals)) / (10 ** 2) / BYTES_PER_TIB;
        assertEq(result1, expected1, "Failed for $12.50");

        // Test $5.75
        uint256 result2 = deployer.calculateUsdfcPerBytePublic(575, 2, tokenDecimals);
        uint256 expected2 = (575 * (10 ** tokenDecimals)) / (10 ** 2) / BYTES_PER_TIB;
        assertEq(result2, expected2, "Failed for $5.75");

        // Test $9.99
        uint256 result3 = deployer.calculateUsdfcPerBytePublic(999, 2, tokenDecimals);
        uint256 expected3 = (999 * (10 ** tokenDecimals)) / (10 ** 2) / BYTES_PER_TIB;
        assertEq(result3, expected3, "Failed for $9.99");

        // Test $2.500 (3 decimals)
        uint256 result4 = deployer.calculateUsdfcPerBytePublic(2500, 3, tokenDecimals);
        uint256 expected4 = (2500 * (10 ** tokenDecimals)) / (10 ** 3) / BYTES_PER_TIB;
        assertEq(result4, expected4, "Failed for $2.500");

        // Test $7.5 (1 decimal)
        uint256 result5 = deployer.calculateUsdfcPerBytePublic(75, 1, tokenDecimals);
        uint256 expected5 = (75 * (10 ** tokenDecimals)) / (10 ** 1) / BYTES_PER_TIB;
        assertEq(result5, expected5, "Failed for $7.5");
    }

    function test_calculateUsdfcPerByte_DifferentTokenDecimals() public view {
        // Test with different token decimal configurations
        uint256 usdPerTibScaled = 1275; // $12.75
        uint8 priceDecimals = 2;

        // Test various token decimals
        uint8[5] memory tokenDecimals = [uint8(6), uint8(8), uint8(12), uint8(18), uint8(2)];

        for (uint256 i = 0; i < tokenDecimals.length; i++) {
            uint8 decimals = tokenDecimals[i];
            uint256 result = deployer.calculateUsdfcPerBytePublic(usdPerTibScaled, priceDecimals, decimals);
            uint256 expected = (1275 * (10 ** decimals)) / (10 ** 2) / BYTES_PER_TIB;

            assertEq(result, expected, string.concat("Failed for token decimals: ", vm.toString(decimals)));
        }
    }

    function testFuzz_calculateUsdfcPerByte(uint128 scaledPrice, uint8 priceDecimals, uint8 tokenDecimals)
        public
        view
    {
        // Bound inputs to reasonable ranges
        scaledPrice = uint128(bound(scaledPrice, 1, type(uint64).max)); // Reasonable price range
        priceDecimals = uint8(bound(priceDecimals, 0, 12)); // Limit to reasonable decimal range
        tokenDecimals = uint8(bound(tokenDecimals, 0, 18)); // Standard token decimal range

        uint256 result = deployer.calculateUsdfcPerBytePublic(scaledPrice, priceDecimals, tokenDecimals);

        // Verify the calculation manually
        uint256 expected = (uint256(scaledPrice) * (10 ** tokenDecimals)) / (10 ** priceDecimals) / BYTES_PER_TIB;
        assertEq(result, expected, "Fuzz test calculation mismatch");

        // Basic sanity check: result should be non-zero if the calculation doesn't underflow
        uint256 usdfcPerTib = (uint256(scaledPrice) * (10 ** tokenDecimals)) / (10 ** priceDecimals);
        if (usdfcPerTib >= BYTES_PER_TIB) {
            assertGt(result, 0, "Result should be non-zero when calculation doesn't underflow");
        }
    }
}
