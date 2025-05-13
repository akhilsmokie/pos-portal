// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "lib/forge-std/src/Test.sol";
import {ERC721Predicate} from "contracts/root/TokenPredicates/ERC721Predicate.sol";
import {ERC721PredicateProxy} from "contracts/root/TokenPredicates/ERC721PredicateProxy.sol";
import {DummyERC721} from "contracts/root/RootToken/DummyERC721.sol";

contract ERC721PredicateTest is Test {
    ERC721Predicate internal erc721Predicate;
    ERC721Predicate internal erc721PredicateImpl;
    DummyERC721 internal erc721Token;
    address internal manager = makeAddr("manager");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal tokenId = 0x1337;
    uint256 internal tokenId2 = tokenId % 2;

    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event LockedERC721(
        address indexed depositor,
        address indexed depositReceiver,
        address indexed rootToken,
        uint256 tokenId
    );
    event LockedERC721Batch(
        address indexed depositor,
        address indexed depositReceiver,
        address indexed rootToken,
        uint256[] tokenIds
    );

    event ExitedERC721(
        address indexed exitor,
        address indexed rootToken,
        uint256 tokenId
    );
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

    function setUp() public {
        erc721Token = new DummyERC721("Test", "TST");
        vm.prank(manager);

        erc721PredicateImpl = new ERC721Predicate();
        address erc721PredicateProxy = address(new ERC721PredicateProxy(address(erc721PredicateImpl)));
        erc721Predicate = ERC721Predicate(erc721PredicateProxy);

        erc721Predicate.initialize(manager);

        vm.startPrank(alice);
        erc721Token.mint(tokenId);
        erc721Token.setApprovalForAll(address(erc721Predicate), true);
        vm.stopPrank();
    }

    function testAliceBalanceAndApproval() public {
        assertEq(erc721Token.ownerOf(tokenId), alice);
        assertEq(erc721Token.balanceOf(address(erc721Predicate)), 0);
        assertTrue(
            erc721Token.isApprovedForAll(alice, address(erc721Predicate))
        );
        assertFalse(
            erc721Token.isApprovedForAll(address(erc721Predicate), alice)
        );
    }

    function testInitialize() public {
        vm.expectRevert("already inited");
        erc721Predicate.initialize(manager);

        address erc721PredicateProxy = address(new ERC721PredicateProxy(address(erc721PredicateImpl)));
        erc721Predicate = ERC721Predicate(erc721PredicateProxy);

        vm.expectEmit();
        emit RoleGranted(
            erc721Predicate.DEFAULT_ADMIN_ROLE(),
            manager,
            address(this)
        );
        vm.expectEmit();
        emit RoleGranted(
            erc721Predicate.MANAGER_ROLE(),
            manager,
            address(this)
        );

        erc721Predicate.initialize(manager);
    }

    function testInitializeImpl() public {
        vm.expectRevert("already inited");
        erc721PredicateImpl.initialize(manager);

        erc721PredicateImpl = new ERC721Predicate();

        vm.expectRevert("already inited");
        erc721PredicateImpl.initialize(manager);
    }

    function testLockTokensInvalidSender() public {
        bytes memory depositData = abi.encode(tokenId);
        vm.expectRevert("ERC721Predicate: INSUFFICIENT_PERMISSIONS");
        erc721Predicate.lockTokens(
            alice /* depositor */,
            bob /* depositReceiver */,
            address(erc721Token),
            depositData
        );
    }

    function testLockTokens() public {
        bytes memory depositData = abi.encode(tokenId);

        assertEq(erc721Token.ownerOf(tokenId), alice);
        assertEq(erc721Token.balanceOf(address(erc721Predicate)), 0);
        assertEq(erc721Token.balanceOf(bob), 0);

        vm.expectEmit();
        emit LockedERC721(alice, bob, address(erc721Token), tokenId);
        vm.expectEmit();
        emit Transfer(alice, address(erc721Predicate), tokenId);

        vm.prank(manager);
        erc721Predicate.lockTokens(
            alice,
            bob,
            address(erc721Token),
            depositData
        );

        assertEq(erc721Token.balanceOf(alice), 0);
        assertEq(erc721Token.ownerOf(tokenId), address(erc721Predicate));
        assertEq(erc721Token.balanceOf(bob), 0);
    }

    function testLockBatchTokensExceedsBatchLimit() public {
        uint256 limit = erc721Predicate.BATCH_LIMIT();
        uint256[] memory tokenIds = new uint256[](limit + 1);
        bytes memory depositData = abi.encode(tokenIds);

        vm.expectRevert("ERC721Predicate: EXCEEDS_BATCH_LIMIT");

        vm.prank(manager);
        erc721Predicate.lockTokens(
            alice,
            bob,
            address(erc721Token),
            depositData
        );
    }

    function testLockBatchTokens() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId;
        tokenIds[1] = tokenId2;
        bytes memory depositData = abi.encode(tokenIds);
        vm.prank(alice);
        erc721Token.mint(tokenId2);

        assertEq(erc721Token.ownerOf(tokenId), alice);
        assertEq(erc721Token.ownerOf(tokenId2), alice);
        assertEq(erc721Token.balanceOf(address(erc721Predicate)), 0);

        vm.expectEmit();
        emit LockedERC721Batch(alice, bob, address(erc721Token), tokenIds);
        vm.expectEmit();
        emit Transfer(alice, address(erc721Predicate), tokenId);

        vm.prank(manager);
        erc721Predicate.lockTokens(
            alice,
            bob,
            address(erc721Token),
            depositData
        );

        assertEq(erc721Token.balanceOf(alice), 0);
        assertEq(erc721Token.ownerOf(tokenId), address(erc721Predicate));
        assertEq(erc721Token.ownerOf(tokenId2), address(erc721Predicate));
    }

    function testLockTokensInsufficientBalance() public {
        bytes memory depositData = abi.encode(tokenId);
        vm.expectRevert("ERC721: transfer of token that is not own");
        vm.prank(manager);
        erc721Predicate.lockTokens(
            bob /* depositor */,
            alice /* depositReceiver */,
            address(erc721Token),
            depositData
        );
    }

    function testLockTokensInsufficientAllowance() public {
        vm.prank(bob);
        erc721Token.mint(tokenId2);
        bytes memory depositData = abi.encode(tokenId2);
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        vm.prank(manager);
        erc721Predicate.lockTokens(
            bob /* depositor */,
            alice /* depositReceiver */,
            address(erc721Token),
            depositData
        );
    }

    function testExitTokensInvalidSender() public {
        bytes memory depositData = abi.encode(tokenId);
        vm.expectRevert("ERC721Predicate: INSUFFICIENT_PERMISSIONS");
        erc721Predicate.exitTokens(address(0x00), address(erc721Token), "0x");
    }

    function testExitTokensInsufficientTokensLocked() public {
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc721Transfer";
        inputs[4] = vm.toString(
            abi.encode(
                alice,
                address(0),
                tokenId,
                erc721Predicate.TRANSFER_EVENT_SIG()
            )
        );
        bytes memory res = vm.ffi(inputs);

        vm.expectRevert("ERC721: transfer of token that is not own");
        vm.prank(manager);
        erc721Predicate.exitTokens(address(0x00), address(erc721Token), res);
    }

    function testExitTokensInvalidSignature() public {
        vm.prank(manager);
        erc721Predicate.lockTokens(
            alice,
            bob,
            address(erc721Token),
            abi.encode(tokenId)
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc721Transfer";
        inputs[4] = vm.toString(
            abi.encode(
                alice,
                address(0),
                tokenId,
                keccak256("0x1337") /* erc721Predicate.TRANSFER_EVENT_SIG() */
            )
        );
        bytes memory res = vm.ffi(inputs);

        vm.expectRevert("ERC721Predicate: INVALID_SIGNATURE");
        vm.prank(manager);
        erc721Predicate.exitTokens(address(0x00), address(erc721Token), res);
    }

    function testExitTokensInvalidReceiver() public {
        vm.prank(manager);
        erc721Predicate.lockTokens(
            alice,
            bob,
            address(erc721Token),
            abi.encode(tokenId)
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc721Transfer";
        inputs[4] = vm.toString(
            abi.encode(
                alice,
                bob /* address(0) */,
                tokenId,
                erc721Predicate.TRANSFER_EVENT_SIG()
            )
        );
        bytes memory res = vm.ffi(inputs);

        vm.expectRevert("ERC721Predicate: INVALID_RECEIVER");
        vm.prank(manager);
        erc721Predicate.exitTokens(address(0x00), address(erc721Token), res);
    }

    function testExitTokens() public {
        assertEq(erc721Token.ownerOf(tokenId), alice);
        assertEq(erc721Token.balanceOf(address(erc721Predicate)), 0);

        vm.prank(manager);
        erc721Predicate.lockTokens(
            alice,
            bob,
            address(erc721Token),
            abi.encode(tokenId)
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc721Transfer";
        inputs[4] = vm.toString(
            abi.encode(
                alice,
                address(0),
                tokenId,
                erc721Predicate.TRANSFER_EVENT_SIG()
            )
        );
        bytes memory res = vm.ffi(inputs);

        assertEq(erc721Token.balanceOf(alice), 0);
        assertEq(erc721Token.ownerOf(tokenId), address(erc721Predicate));

        vm.expectEmit();
        emit ExitedERC721(alice, address(erc721Token), tokenId);
        vm.prank(manager);
        erc721Predicate.exitTokens(address(0x00), address(erc721Token), res);

        assertEq(erc721Token.ownerOf(tokenId), alice);
        assertEq(erc721Token.balanceOf(address(erc721Predicate)), 0);
    }
}
