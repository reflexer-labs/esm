pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import { ESM } from "./ESM.sol";

contract GlobalSettlementMock {
    uint256 public contractEnabled;

    constructor() public { contractEnabled = 1; }
    function shutdownSystem() public { contractEnabled = 0; }
}

contract ESMThresholdSetter {
    ESM public esm;

    function modifyParameters(bytes32, address account) public {
        esm = ESM(account);
    }

    function recomputeThreshold() public {
        esm.modifyParameters("triggerThreshold", esm.triggerThreshold() + 1);
    }
}

contract TestUsr {
    DSToken protocolToken;

    constructor(DSToken protocolToken_) public {
        protocolToken = protocolToken_;
    }
    function callShutdown(ESM esm, uint approval) external {
        protocolToken.approve(address(esm), approval);
        esm.shutdown();
    }
}

contract ESMTest is DSTest {
    ESM     esm;
    DSToken protocolToken;
    GlobalSettlementMock globalSettlement;
    ESMThresholdSetter thresholdSetter;
    uint256 triggerThreshold;
    address tokenBurner;
    TestUsr usr;
    TestUsr gov;

    function setUp() public {
        protocolToken = new DSToken("PROT");
        protocolToken.mint(1000000 ether);
        globalSettlement = new GlobalSettlementMock();
        gov = new TestUsr(protocolToken);
        tokenBurner = address(0x42);
        protocolToken.transfer(address(gov), 1 ether);
    }

    function test_constructor_without_threshold_setter() public {
        esm = makeWithCapWithoutThresholdSetter(10);

        assertEq(address(esm.protocolToken()), address(protocolToken));
        assertEq(address(esm.globalSettlement()), address(globalSettlement));
        assertEq(esm.triggerThreshold(), 10);
        assertEq(esm.settled(), 0);
    }

    function test_constructor_with_threshold_setter() public {
        thresholdSetter = new ESMThresholdSetter();
        esm = makeWithCapWithThresholdSetter(address(thresholdSetter), 10);
        thresholdSetter.modifyParameters("esm", address(esm));

        assertEq(address(esm.protocolToken()), address(protocolToken));
        assertEq(address(esm.globalSettlement()), address(globalSettlement));
        assertEq(address(esm.thresholdSetter()), address(thresholdSetter));
        assertEq(esm.triggerThreshold(), 10);
        assertEq(esm.settled(), 0);
    }

    function testFail_set_low_threshold() public {
        esm = makeWithCapWithoutThresholdSetter(10);
        esm.modifyParameters(bytes32("triggerThreshold"), 0);
    }

    function testFail_set_high_threshold() public {
        esm = makeWithCapWithoutThresholdSetter(10);
        esm.modifyParameters(bytes32("triggerThreshold"), 1000001 ether);
    }

    function testFail_construct_zero_threshold() public {
        esm = makeWithCapWithoutThresholdSetter(0);
    }

    function testFail_construct_threshold_above_supply() public {
        esm = makeWithCapWithoutThresholdSetter(1000001 ether);
    }

    function test_set_threshold() public {
        esm = makeWithCapWithoutThresholdSetter(10);
        assertEq(esm.triggerThreshold(), 10);
        esm.modifyParameters(bytes32("triggerThreshold"), 15);
        assertEq(esm.triggerThreshold(), 15);
    }

    function test_shutdown_no_threshold_setter() public {
        esm = makeWithCapWithoutThresholdSetter(1);
        gov.callShutdown(esm, 1);

        assertEq(esm.settled(), 1);
        assertEq(globalSettlement.contractEnabled(), 0);
    }

    function test_shutdown_with_threshold_setter() public {
        thresholdSetter = new ESMThresholdSetter();
        esm = makeWithCapWithThresholdSetter(address(thresholdSetter), 1);
        thresholdSetter.modifyParameters("esm", address(esm));
        gov.callShutdown(esm, 2);

        assertEq(esm.settled(), 1);
        assertEq(globalSettlement.contractEnabled(), 0);
    }

    function testFail_shutdown_twice() public {
        esm = makeWithCapWithoutThresholdSetter(1);
        gov.callShutdown(esm, 1);
        gov.callShutdown(esm, 1);
    }

    // -- internal test helpers --
    function makeWithCapWithoutThresholdSetter(uint256 threshold_) internal returns (ESM) {
        return new ESM(address(protocolToken), address(globalSettlement), tokenBurner, address(0), threshold_);
    }
    function makeWithCapWithThresholdSetter(address setter_, uint256 threshold_) internal returns (ESM) {
        return new ESM(address(protocolToken), address(globalSettlement), tokenBurner, setter_, threshold_);
    }
}
