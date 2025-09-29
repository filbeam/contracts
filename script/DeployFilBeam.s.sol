// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/FilBeam.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

/**
 * @title DeployFilBeam
 * @dev Deploys FilBeam contract with USDFC token integration
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Deployer's private key
 * - FWSS_ADDRESS: Address of the FWSS contract
 * - USDFC_ADDRESS: Address of the USDFC ERC20 token contract
 * - CDN_PRICE_USD_PER_TIB: CDN egress price in USD per TiB (scaled by PRICE_DECIMALS, e.g., 1250 for $12.50/TiB)
 * - CACHE_MISS_PRICE_USD_PER_TIB: Cache miss price in USD per TiB (scaled by PRICE_DECIMALS, e.g., 1575 for $15.75/TiB)
 * - PRICE_DECIMALS: Number of decimal places for price inputs (e.g., 2 for cents, 0 for whole dollars)
 *
 * Example usage:
 * PRIVATE_KEY=0x123... FWSS_ADDRESS=0xabc... USDFC_ADDRESS=0xdef... CDN_PRICE_USD_PER_TIB=1250 CACHE_MISS_PRICE_USD_PER_TIB=1575 PRICE_DECIMALS=2 forge script script/DeployFilBeam.s.sol --broadcast
 */
contract DeployFilBeam is Script {
    // Constants for conversion
    uint256 constant BYTES_PER_TIB = 1024 * 1024 * 1024 * 1024; // 1 TiB in bytes

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get environment variables
        address fwssAddress = vm.envAddress("FWSS_ADDRESS");
        address usdfcAddress = vm.envAddress("USDFC_ADDRESS");

        // Get USD prices per TiB (scaled by PRICE_DECIMALS, e.g., 1250 for $12.50/TiB with 2 decimals)
        uint256 cdnPriceUsdPerTibScaled = vm.envUint("CDN_PRICE_USD_PER_TIB");
        uint256 cacheMissPriceUsdPerTibScaled = vm.envUint("CACHE_MISS_PRICE_USD_PER_TIB");
        uint8 priceDecimals = uint8(vm.envUint("PRICE_DECIMALS"));

        // Query USDFC contract for decimals
        IERC20 usdfcContract = IERC20(usdfcAddress);
        uint8 usdfcDecimals = usdfcContract.decimals();

        // Calculate USDFC per byte rates
        uint256 cdnRatePerByte = calculateUsdfcPerByte(cdnPriceUsdPerTibScaled, priceDecimals, usdfcDecimals);
        uint256 cacheMissRatePerByte = calculateUsdfcPerByte(cacheMissPriceUsdPerTibScaled, priceDecimals, usdfcDecimals);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract
        FilBeam implementation = new FilBeam();

        // Encode the initialize call
        bytes memory initData =
            abi.encodeCall(FilBeam.initialize, (fwssAddress, cdnRatePerByte, cacheMissRatePerByte, deployer));

        // Deploy the proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        vm.stopBroadcast();

        // Log deployment information
        console2.log("=== FilBeam Deployment Complete ===");
        console2.log("Implementation deployed at:", address(implementation));
        console2.log("Proxy deployed at:", address(proxy));
        console2.log("FilBeam contract available at:", address(proxy));
        console2.log("");
        console2.log("=== Configuration ===");
        console2.log("FWSS Address:", fwssAddress);
        console2.log("USDFC Address:", usdfcAddress);
        console2.log("USDFC Decimals:", usdfcDecimals);
        console2.log("Price Decimals:", priceDecimals);
        console2.log("Owner:", deployer);
        console2.log("");
        console2.log("=== Pricing ===");
        console2.log("CDN Price (scaled input):", cdnPriceUsdPerTibScaled);
        console2.log("CDN Rate (USDFC per byte):", cdnRatePerByte);
        console2.log("Cache Miss Price (scaled input):", cacheMissPriceUsdPerTibScaled);
        console2.log("Cache Miss Rate (USDFC per byte):", cacheMissRatePerByte);

        if (priceDecimals > 0) {
            console2.log("");
            console2.log("=== Actual USD Prices ===");
            console2.log("CDN: scaled %d with %d decimals", cdnPriceUsdPerTibScaled, priceDecimals);
            console2.log("Cache Miss: scaled %d with %d decimals", cacheMissPriceUsdPerTibScaled, priceDecimals);
        }
    }

    /**
     * @dev Converts USD per TiB to USDFC per byte with decimal price support
     * @param usdPerTibScaled Price in USD per TiB scaled by priceDecimals (e.g., 1250 for $12.50/TiB with 2 decimals)
     * @param priceDecimals Number of decimal places in the price input (e.g., 2 for cents)
     * @param tokenDecimals Number of decimal places in the USDFC token
     * @return USDFC per byte (scaled by USDFC token decimals)
     */
    function calculateUsdfcPerByte(uint256 usdPerTibScaled, uint8 priceDecimals, uint8 tokenDecimals) internal pure returns (uint256) {
        // Convert scaled USD to USDFC (assuming 1:1 parity)
        // Account for price decimals: 1250 with 2 decimals = $12.50
        // Scale by USDFC token decimals (e.g., 6 decimals = 10^6)
        uint256 usdfcPerTib = (usdPerTibScaled * (10 ** tokenDecimals)) / (10 ** priceDecimals);

        // Convert per TiB to per byte
        uint256 usdfcPerByte = usdfcPerTib / BYTES_PER_TIB;

        return usdfcPerByte;
    }
}
