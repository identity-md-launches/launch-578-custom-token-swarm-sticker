// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmSticker} from "../src/SwarmSticker.sol";

/// @dev Local launch-flow helper; this does not implement a real DEX or launch factory.
contract DeploymentProbe {
    function deploy(bytes32 salt) external returns (SwarmSticker) {
        return new SwarmSticker{salt: salt}();
    }

    function move(SwarmSticker token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// forge-config: default.fuzz.runs = 1000
contract SwarmStickerTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    SwarmSticker private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SwarmSticker();
    }

    function testMetadataAndInitialSupply() public view {
        assertEq(token.name(), "Swarm Sticker");
        assertEq(token.symbol(), "STICK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testConstructorEmitsMintAndMintsToImmediateCaller() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        SwarmSticker other = new SwarmSticker();
        assertEq(other.balanceOf(ALICE), SUPPLY);
        assertEq(other.balanceOf(address(this)), 0);
        assertEq(other.totalSupply(), SUPPLY);
    }

    function testCreate2FactoryReceivesEntireSupply() public {
        DeploymentProbe factory = new DeploymentProbe();
        bytes32 salt = keccak256("STICK launch");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(SwarmSticker).creationCode)
                        )
                    )
                )
            )
        );
        SwarmSticker launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
    }

    function testTransferEmitsEventAndDeliversExactAmount() public {
        uint256 amount = 123 ether;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, amount);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testEntireSupplyCanMove() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testSelfTransferDoesNotChangeBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferRejectsInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testSelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(ALICE, 1);
    }

    function testTransferRejectsZeroRecipientEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalEmitsEventAndCanBeReplacedAndRevoked() public {
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 50 ether);
        assertTrue(token.approve(SPENDER, 50 ether));
        assertEq(token.allowance(address(this), SPENDER), 50 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function testApprovalDoesNotRequireBalanceOrMoveTokens() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApprovalRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function testTransferFromConsumesFiniteAllowance() public {
        assertTrue(token.approve(SPENDER, 20 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 7 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 7 ether));
        assertEq(token.allowance(address(this), SPENDER), 13 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 13 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 7 ether);
        assertEq(token.balanceOf(BOB), 13 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
    }

    function testTransferFromPreservesInfiniteAllowance() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function testTransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromZeroAmountNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function testTransferFromRejectsInsufficientAllowanceWithoutMutation() public {
        assertTrue(token.approve(SPENDER, 3 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 3 ether, 4 ether)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 4 ether);
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTransferFromRejectsUnapprovedCaller() public {
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testDeployerCannotSpendHoldersTokensWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 100 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    function testTransferFromBalanceFailureRestoresAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10 ether);
        assertEq(token.allowance(ALICE, SPENDER), 10 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testTransferFromRejectsZeroRecipientAndRestoresAllowance() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 1);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromRejectsZeroSenderEvenForZeroAmount() public {
        // OpenZeppelin validates the allowance owner before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function testLaunchAllocationClaimsAndPoolTransfersArriveWhole() public {
        DeploymentProbe factory = new DeploymentProbe();
        SwarmSticker launched = factory.deploy(bytes32(uint256(1)));
        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 8_800 / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;
        assertTrue(factory.move(launched, distributor, swarm));
        assertTrue(factory.move(launched, poolManager, pool));
        assertTrue(factory.move(launched, BOB, remainder));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), 100_000_000 ether);
        assertEq(launched.balanceOf(poolManager), 880_000_000 ether);
        assertEq(launched.balanceOf(BOB), 20_000_000 ether);

        vm.prank(distributor);
        assertTrue(launched.transfer(ALICE, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(ALICE), swarm);
        vm.prank(poolManager);
        assertTrue(launched.transfer(ALICE, 123 ether));
        assertEq(launched.balanceOf(ALICE), swarm + 123 ether);
        vm.prank(ALICE);
        assertTrue(launched.transfer(poolManager, 23 ether));
        vm.prank(ALICE);
        assertTrue(launched.approve(SPENDER, 100 ether));
        vm.prank(SPENDER);
        assertTrue(launched.transferFrom(ALICE, poolManager, 100 ether));
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testNoAdminMintBurnOrUpgradeEntrypoints() public {
        assertTrue(token.transfer(ALICE, 100 ether));
        bytes[] memory calls = new bytes[](21);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("setOwner(address)", BOB);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[7] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[8] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[9] = abi.encodeWithSignature("pause()");
        calls[10] = abi.encodeWithSignature("unpause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[12] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[13] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[14] = abi.encodeWithSignature("lock(address)", ALICE);
        calls[15] = abi.encodeWithSignature("disableTransfers()");
        calls[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[17] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 100 ether);
        calls[18] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[19] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[20] = abi.encodeWithSignature("owner()");
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unexpected entrypoint");
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger reached an unexpected entrypoint");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function testNativeETHAndUnknownCallsAreRejected() public {
        vm.deal(address(this), 1 ether);
        (bool sent,) = address(token).call{value: 1 ether}("");
        assertFalse(sent);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
        assertEq(address(token).balance, 0);
    }

    function testRuntimeHasNoForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 opcode = uint8(code[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden runtime opcode");
        }
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        if (recipient == address(this)) recipient = ALICE;
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromAccountsExactly(uint256 allowanceAmount, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        allowanceAmount = bound(allowanceAmount, amount, type(uint256).max);
        assertTrue(token.approve(SPENDER, allowanceAmount));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(
            token.allowance(address(this), SPENDER),
            allowanceAmount == type(uint256).max ? allowanceAmount : allowanceAmount - amount
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzExcessTransferReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzzExcessAllowanceSpendReverts(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
