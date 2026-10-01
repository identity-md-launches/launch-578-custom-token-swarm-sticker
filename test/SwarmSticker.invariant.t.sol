// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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
        amount = amount % 5 == 0 ? type(uint256).max : bound(amount, 0, 1_000_000_000 ether);
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
        vm.prank(address(0xBAD));
        (bool success,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, 1)));
        assertFalse(success);
    }
}

contract SwarmStickerInvariantTest is Test {
    SwarmSticker private token;
    StickerHandler private handler;

    function setUp() public {
        token = new SwarmSticker();
        handler = new StickerHandler(token);
        assertTrue(token.transfer(handler.actors(0), 1_000_000_000 ether));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = StickerHandler.move.selector;
        selectors[1] = StickerHandler.approve.selector;
        selectors[2] = StickerHandler.spend.selector;
        selectors[3] = StickerHandler.rejectUnauthorizedSpend.selector;
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
}
