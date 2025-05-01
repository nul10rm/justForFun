// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {TramEVController, U3Wrap1, U3Wrap2, GLDToken, SLVToken} from "../src/TramEVController.sol";

contract SetupScript is Script {
    TramEVController public mev;
    GLDToken gld;
    SLVToken slv;

    event log_named_address(string memo, address);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        address[] memory tokens = new address[](6);
        gld = new GLDToken(100_000_000 * 1e18);
        slv = new SLVToken(100_000_000 * 1e18);

        // emit log_named_address("GLD", address(gld));
        // emit log_named_address("SLV", address(slv));

        tokens[0] = address(gld);
        tokens[1] = address(slv);
        tokens[2] = address(gld);
        tokens[3] = address(slv);
        tokens[4] = address(gld);
        tokens[5] = address(slv);

        mev = new TramEVController(address(1337), tokens, address(new U3Wrap1()), address(new U3Wrap2()));
        emit log_named_address("Deployed to", address(mev));

        gld.transfer(address(mev), 100_000_000 * 1e18);
        slv.transfer(address(mev), 100_000_000 * 1e18);

        (bool success, bytes memory ret) = address(mev).call(
            abi.encodePacked(
                abi.encode(address(gld), address(slv), uint24(1), uint256(1), uint256(99_999_999 * 1e18)), uint8(37)
            )
        ); // goal - drain silver

        if (!success) {
            revert(string(ret));
        }
        vm.stopBroadcast();
    }
}
