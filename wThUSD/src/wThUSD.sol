// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*
▗▄▄▄▖▗▖ ▗▖ ▗▄▖ ▗▄▄▖ ▗▖ ▗▖ ▗▄▖ 
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌
  █  ▐▛▀▜▌▐▛▀▜▌▐▛▀▚▖▐▌ ▐▌▐▛▀▜▌
  █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▙█▟▌▐▌ ▐▌


visit : https://tharwa.finance                         
*/

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TharwaWrapper} from "src/TharwaWrapper.sol";

contract wThUSD is TharwaWrapper {
    constructor(IERC20 _thUsd) TharwaWrapper(_thUsd, "Wrapped ThUSD", "wThUSD") {}
}
