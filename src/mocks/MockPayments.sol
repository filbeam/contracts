// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPayments {
    struct RailView {
        IERC20 token;
        address from;
        address to;
        address operator;
        address validator;
        uint256 paymentRate;
        uint256 lockupPeriod;
        uint256 lockupFixed;
        uint256 settledUpTo;
        uint256 endEpoch;
        uint256 commissionRateBps;
        address serviceFeeRecipient;
    }

    mapping(uint256 => RailView) public rails;
    mapping(uint256 => bool) public railExists;

    function setRail(uint256 railId, RailView memory rail) external {
        rails[railId] = rail;
        railExists[railId] = true;
    }

    function getRail(uint256 railId) external view returns (RailView memory) {
        require(railExists[railId], "Rail does not exist");
        return rails[railId];
    }

    function setLockupFixed(uint256 railId, uint256 lockupFixed) external {
        require(railExists[railId], "Rail does not exist");
        rails[railId].lockupFixed = lockupFixed;
    }

    function setRailExists(uint256 railId, bool exists) external {
        railExists[railId] = exists;
    }
}
