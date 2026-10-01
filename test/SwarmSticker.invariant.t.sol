// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmSticker} from "../src/SwarmSticker.sol";

/// @dev Independent balance/allowance model over a closed set of holders.
contract StickerHandler is Test {
    SwarmSticker public immutable token;
    address[4] public actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SwarmSticker token_) {
        token = token_;
        expectedBalance[actors[0]] = 1_000_000_000 ether;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 mode = amount % 5;
        if (mode == 0) amount = type(uint256).max;
        else if (mode == 1) amount = type(uint256).max - 1;
        else if (mode == 2) amount = 0;
        else amount = bound(amount, 0, 1_000_000_000 ether);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function rejectUnauthorizedSpend(uint256 ownerSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        // This caller is outside the set of approved spenders for every sequence.
        _reject(
            address(0xBAD),
            abi.encodeCall(token.transferFrom, (owner, to, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(0xBAD), 0, 1)
        );
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function rejectExcessBalance(uint256 ownerSeed, uint256 toSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        if (delegated) {
            // An approved spend must still roll back if the owner's funds are insufficient.
            vm.prank(owner);
            assertTrue(token.approve(to, amount));
            expectedAllowance[owner][to] = amount;
            _reject(to, abi.encodeCall(token.transferFrom, (owner, to, amount)), error);
            assertEq(token.allowance(owner, to), amount, "failed spend consumed approval");
        } else {
            _reject(owner, abi.encodeCall(token.transfer, (to, amount)), error);
        }
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 approved) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        approved = bound(approved, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, approved + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            vm.prank(owner);
            assertTrue(token.approve(spender, amount));
            expectedAllowance[owner][spender] = amount;
            _reject(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), error);
        } else {
            _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), error);
        }
    }

    function moveFullBalanceAndBack(uint256 fromSeed, uint256 toSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0, "full transfer left a balance");
        assertEq(token.balanceOf(to), toBefore + amount, "recipient received less than sent");
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), amount, "round trip changed sender funds");
        assertEq(token.balanceOf(to), toBefore, "round trip changed recipient funds");
        // The independent model stays unchanged: a fee-free round trip is the identity.
    }

    function _reject(address caller, bytes memory data, bytes memory error) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, error, "operation reverted for the wrong reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmStickerInvariantTest is Test {
    SwarmSticker private token;
    StickerHandler private handler;

    function setUp() public {
        token = new SwarmSticker();
        handler = new StickerHandler(token);
        assertTrue(token.transfer(handler.actors(0), 1_000_000_000 ether));
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = StickerHandler.move.selector;
        selectors[1] = StickerHandler.approve.selector;
        selectors[2] = StickerHandler.spend.selector;
        selectors[3] = StickerHandler.rejectUnauthorizedSpend.selector;
        selectors[4] = StickerHandler.revoke.selector;
        selectors[5] = StickerHandler.rejectExcessBalance.selector;
        selectors[6] = StickerHandler.rejectExcessAllowance.selector;
        selectors[7] = StickerHandler.rejectZeroRecipient.selector;
        selectors[8] = StickerHandler.moveFullBalanceAndBack.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariantSupplyAndBalancesMatchModel() public view {
        uint256 total;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            total += balance;
        }
        assertEq(total, 1_000_000_000 ether);
        assertEq(token.totalSupply(), total);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0xBAD)), 0);
    }

    function invariantAllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariantMetadataDoesNotChange() public view {
        assertEq(token.name(), "Swarm Sticker");
        assertEq(token.symbol(), "STICK");
        assertEq(token.decimals(), 18);
    }

    /// @dev Every holder can move all funds after any generated sequence, including failed calls.
    function afterInvariant() public {
        address recipient = address(0xCAFE);
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = handler.expectedBalance(actor);
            vm.prank(actor);
            assertTrue(token.transfer(recipient, balance));
            assertEq(token.balanceOf(actor), 0);
        }
        assertEq(token.balanceOf(recipient), 1_000_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function testHandlerBoundarySequence() public {
        handler.approve(0, 1, 0); // Infinite approval.
        handler.spend(0, 1, 2, 1);
        handler.revoke(0, 1);
        handler.approve(0, 1, 1); // Largest finite approval.
        handler.spend(0, 1, 0, 1); // Delegated self-transfer.
        handler.rejectExcessBalance(0, 1, type(uint256).max, true);
        handler.rejectExcessBalance(2, 2, type(uint256).max, false);
        handler.rejectExcessAllowance(0, 1, type(uint256).max - 1);
        handler.rejectZeroRecipient(0, 1, 1, true);
        handler.rejectZeroRecipient(3, 2, 0, false);
        handler.rejectUnauthorizedSpend(0, 1);
        handler.moveFullBalanceAndBack(0, 2);
        handler.move(2, 3, 1);
        invariantSupplyAndBalancesMatchModel();
        invariantAllowancesMatchModel();
        invariantMetadataDoesNotChange();
        afterInvariant();
    }
}
