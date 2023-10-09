// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {WrappedFriendtech} from "src/WrappedFriendtech.sol";

contract WrappedFriendtechScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        new WrappedFriendtech(vm.envAddress("OWNER"));
    }
}
