// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmSticker} from "src/SwarmSticker.sol";

/// @dev Complements the existing deployment and launch-flow tests with allowance lifecycle failures.
/// forge-config: default.fuzz.runs = 1000
contract SwarmStickerAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant OTHER_SPENDER = address(0x5EEE);

    SwarmSticker private token;

    function setUp() public {
        token = new SwarmSticker();
    }

    function testMaximumTransferCannotWrapBalancesOrSpendUnlimitedFunds() public {
        bytes memory error = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(error);
        token.transfer(ALICE, type(uint256).max);

        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(error);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testLargestFiniteAllowanceIsConsumed() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), approved - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteAllowanceCanBeRevokedAndReplacedWithFiniteBudget() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.approve(SPENDER, 0));
        _expectAllowanceFailure(SPENDER, address(this), ALICE, 0, 1);

        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        _expectAllowanceFailure(SPENDER, address(this), ALICE, 0, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(ALICE), 2);
    }

    function testReplayingAnExhaustedAllowanceCannotSpendAgain() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        _expectAllowanceFailure(SPENDER, address(this), ALICE, 0, 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function testSelfSpenderNeedsItsOwnAllowanceAndConsumesIt() public {
        assertTrue(token.transfer(ALICE, 2));
        _expectAllowanceFailure(ALICE, ALICE, BOB, 0, 1);
        vm.prank(ALICE);
        assertTrue(token.approve(ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        _expectAllowanceFailure(ALICE, ALICE, BOB, 0, 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, ALICE), 0);
    }

    function testApprovalsAreNotTransitive() public {
        assertTrue(token.transfer(ALICE, 100));
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 100));
        vm.prank(BOB);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        _expectAllowanceFailure(SPENDER, ALICE, SPENDER, 0, 1);
        assertEq(token.allowance(ALICE, BOB), 100);
        assertEq(token.allowance(BOB, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function testZeroSpenderRejectedAtBothApprovalExtremes() public {
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        vm.expectRevert(error);
        token.approve(address(0), 0);
        vm.expectRevert(error);
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testDelegatedZeroTransferToZeroRecipientRevertsWithoutLosingApproval() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplitSpendsCannotExceedCumulativeBudget(uint256 budget, uint256 first) public {
        // Leave funds behind so the final failure is authorization, not an empty account.
        budget = bound(budget, 1, SUPPLY - 1);
        first = bound(first, 0, budget);
        assertTrue(token.approve(SPENDER, budget));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), budget - first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, budget - first));
        _expectAllowanceFailure(SPENDER, address(this), BOB, 0, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), budget - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - budget);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzFailedSpendCanBeRetriedAfterFunding(uint256 held, uint256 amount, uint256 approved) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.transfer(ALICE, held));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);

        assertTrue(token.transfer(ALICE, amount - held));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(ALICE, SPENDER), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzRepeatedRoundTripsAreFeeFree(uint256 aliceFunds, uint256 bobFunds, uint256 amount, uint256 cycles)
        public
    {
        aliceFunds = bound(aliceFunds, 1, SUPPLY);
        bobFunds = bound(bobFunds, 0, SUPPLY - aliceFunds);
        amount = bound(amount, 1, aliceFunds);
        cycles = bound(cycles, 1, 8);
        assertTrue(token.transfer(ALICE, aliceFunds));
        assertTrue(token.transfer(BOB, bobFunds));
        for (uint256 i; i < cycles; ++i) {
            vm.prank(ALICE);
            assertTrue(token.transfer(BOB, amount));
            assertEq(token.balanceOf(ALICE), aliceFunds - amount);
            assertEq(token.balanceOf(BOB), bobFunds + amount);
            vm.prank(BOB);
            assertTrue(token.transfer(ALICE, amount));
            assertEq(token.balanceOf(ALICE), aliceFunds);
            assertEq(token.balanceOf(BOB), bobFunds);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceFunds - bobFunds);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzReplacingAllowanceIsIdempotentAndIsolated(uint256 first, uint256 replacement, uint256 spend)
        public
    {
        assertTrue(token.approve(OTHER_SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, first));
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);

        spend = bound(spend, 0, replacement < SUPPLY ? replacement : SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), SPENDER, spend));
        assertEq(
            token.allowance(address(this), SPENDER),
            replacement == type(uint256).max ? replacement : replacement - spend
        );
        assertEq(token.allowance(address(this), OTHER_SPENDER), type(uint256).max);
        assertEq(token.allowance(SPENDER, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - spend);
        assertEq(token.balanceOf(SPENDER), spend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSpendingOneOwnersApprovalDoesNotSpendAnothers(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY / 2);
        assertTrue(token.transfer(ALICE, amount));
        assertTrue(token.transfer(BOB, amount));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, amount));
        vm.prank(BOB);
        assertTrue(token.approve(SPENDER, amount));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, SPENDER, amount));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(BOB, SPENDER), amount);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(BOB, SPENDER, amount));
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 2 * amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2 * amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectAllowanceFailure(address spender, address owner, address to, uint256 approved, uint256 amount)
        private
    {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }
}
