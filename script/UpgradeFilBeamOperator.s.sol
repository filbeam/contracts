// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/FilBeamOperator.sol";

/**
 * @title UpgradeFilBeamOperator
 * @dev Upgrades an existing FilBeamOperator proxy to a new implementation
 *
 * This script deploys a new implementation contract and upgrades the proxy
 * State is preserved in the proxy - only the implementation logic changes.
 *
 * Note: To preserve existing rates, query them from the current proxy:
 *   cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "cdnRatePerByte()" --rpc-url $RPC_URL
 *   cast call $FILBEAM_OPERATOR_PROXY_ADDRESS "cacheMissRatePerByte()" --rpc-url $RPC_URL
 *
 * Required Environment Variables:
 * - PRIVATE_KEY: Owner's private key (must be contract owner)
 * - FILBEAM_OPERATOR_PROXY_ADDRESS: Address of the existing proxy contract
 * - FWSS_ADDRESS: Address of the FWSS contract
 * - FWSS_STATE_VIEW_ADDRESS: Address of the FWSS State View contract
 * - PAYMENTS_ADDRESS: Address of the Payments contract
 * - CDN_RATE_PER_BYTE: CDN rate per byte in USDFC smallest units
 * - CACHE_MISS_RATE_PER_BYTE: Cache miss rate per byte in USDFC smallest units
 *
 * Example usage:
 * PRIVATE_KEY=0x... FILBEAM_OPERATOR_PROXY_ADDRESS=0x... FWSS_ADDRESS=0x... FWSS_STATE_VIEW_ADDRESS=0x... PAYMENTS_ADDRESS=0x... CDN_RATE_PER_BYTE=100 CACHE_MISS_RATE_PER_BYTE=200 forge script script/UpgradeFilBeamOperator.s.sol --broadcast
 */
contract UpgradeFilBeamOperator is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // The address of existing proxy contract
        address filBeamOperatorProxyAddress = vm.envAddress("FILBEAM_OPERATOR_PROXY_ADDRESS");
        address fwssAddress = vm.envAddress("FWSS_ADDRESS");
        address fwssStateViewAddress = vm.envAddress("FWSS_STATE_VIEW_ADDRESS");
        address paymentsAddress = vm.envAddress("PAYMENTS_ADDRESS");
        uint256 cdnRatePerByte = vm.envUint("CDN_RATE_PER_BYTE");
        uint256 cacheMissRatePerByte = vm.envUint("CACHE_MISS_RATE_PER_BYTE");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new implementation contract
        FilBeamOperator newImplementation = new FilBeamOperator(
            fwssAddress, fwssStateViewAddress, paymentsAddress, cdnRatePerByte, cacheMissRatePerByte
        );

        // Step 2: Upgrade the proxy to point to the new implementation
        FilBeamOperator proxy = FilBeamOperator(filBeamOperatorProxyAddress);
        proxy.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();

        // Step 3: Verify the upgrade
        FilBeamOperator filBeam = FilBeamOperator(filBeamOperatorProxyAddress);
        console2.log("=== FilBeamOperator Upgrade Complete ===");
        console2.log("Proxy Address:", filBeamOperatorProxyAddress);
        console2.log("New Implementation Address:", address(newImplementation));
        console2.log("Contract Version:", filBeam.version());
    }
}
