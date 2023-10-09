// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ERC1155} from "solady/tokens/ERC1155.sol";
import {WrappedFriendtech} from "src/WrappedFriendtech.sol";

interface IFriendtech {
    function getBuyPriceAfterFee(
        address sharesSubject,
        uint256 amount
    ) external view returns (uint256);

    function getSellPriceAfterFee(
        address sharesSubject,
        uint256 amount
    ) external view returns (uint256);

    function getBuyPrice(
        address sharesSubject,
        uint256 amount
    ) external view returns (uint256);

    function buyShares(address sharesSubject, uint256 amount) external payable;

    function sellShares(address sharesSubject, uint256 amount) external;

    function sharesBalance(
        address sharesSubject,
        address owner
    ) external view returns (uint256);

    function sharesSupply(
        address sharesSubject
    ) external view returns (uint256);

    function protocolFeePercent() external view returns (uint256);

    function subjectFeePercent() external view returns (uint256);
}

contract ERC1155TokenReceiver {
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}

contract WrappedFriendtechTest is Test, ERC1155TokenReceiver {
    IFriendtech public constant FRIENDTECH =
        IFriendtech(0xCF205808Ed36593aa40a44F10c7f7C2F67d4A4d4);
    address public constant SHARES_SUBJECT =
        0x5b19B52129be5A8527c2b515fAbA7997b6D1B044;
    uint256 public constant SHARES_SUBJECT_TOKEN_ID =
        uint256(uint160(SHARES_SUBJECT));

    WrappedFriendtech public immutable wrapper =
        new WrappedFriendtech(address(this));
    uint256 public immutable friendtechProtocolFeePercent =
        FRIENDTECH.protocolFeePercent();
    uint256 public immutable friendtechSubjectFeePercent =
        FRIENDTECH.subjectFeePercent();

    event URI(string value, uint256 indexed id);
    event TransferSingle(
        address indexed _operator,
        address indexed _from,
        address indexed _to,
        uint256 _id,
        uint256 _value
    );
    event Trade(
        address trader,
        address subject,
        bool isBuy,
        uint256 shareAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 subjectEthAmount,
        uint256 supply
    );

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                             setBaseURI
    //////////////////////////////////////////////////////////////*/

    function testCannotSetBaseURIUnauthorized() external {
        vm.prank(address(0));
        vm.expectRevert(Ownable.Unauthorized.selector);

        wrapper.setBaseURI("https://test.com");
    }

    function testSetBaseURI() external {
        address msgSender = wrapper.owner();
        string memory newBaseURI = "https://test.com";

        assertTrue(
            keccak256(bytes(newBaseURI)) != keccak256(bytes(wrapper.baseURI()))
        );

        vm.prank(msgSender);
        vm.expectEmit(false, true, false, true, address(wrapper));

        emit URI(newBaseURI, type(uint256).max);

        wrapper.setBaseURI(newBaseURI);

        assertEq(
            keccak256(bytes(newBaseURI)),
            keccak256(bytes(wrapper.baseURI()))
        );
    }

    /*//////////////////////////////////////////////////////////////
                             wrap
    //////////////////////////////////////////////////////////////*/

    function testCannotWrapZeroAmount() external {
        vm.expectRevert(WrappedFriendtech.ZeroAmount.selector);

        wrapper.wrap(SHARES_SUBJECT, 0);
    }

    function testCannotWrapZeroSharesSubject() external {
        vm.expectRevert("Only the shares' subject can buy the first share");

        wrapper.wrap(address(0), 1);
    }

    function testCannotWrapInsufficientMsgValue() external {
        uint256 amount = 1;
        uint256 price = FRIENDTECH.getBuyPriceAfterFee(SHARES_SUBJECT, amount);

        vm.expectRevert();

        wrapper.wrap{value: price - 1}(SHARES_SUBJECT, amount);
    }

    function testWrap() external {
        uint256 amount = 1;
        uint256 price = FRIENDTECH.getBuyPriceAfterFee(SHARES_SUBJECT, amount);
        uint256 priceBeforeFee = FRIENDTECH.getBuyPrice(SHARES_SUBJECT, amount);
        uint256 tokenBalanceBefore = wrapper.balanceOf(
            address(this),
            SHARES_SUBJECT_TOKEN_ID
        );
        uint256 wrapperSharesBalanceBefore = FRIENDTECH.sharesBalance(
            SHARES_SUBJECT,
            address(wrapper)
        );
        uint256 supplyBefore = FRIENDTECH.sharesSupply(SHARES_SUBJECT);

        vm.expectEmit(true, true, true, true, address(wrapper));

        emit TransferSingle(
            address(this),
            address(0),
            address(this),
            SHARES_SUBJECT_TOKEN_ID,
            amount
        );

        vm.expectEmit(false, false, false, true, address(FRIENDTECH));

        emit Trade(
            address(wrapper),
            SHARES_SUBJECT,
            true,
            amount,
            priceBeforeFee,
            (priceBeforeFee * friendtechProtocolFeePercent) / 1 ether,
            (priceBeforeFee * friendtechSubjectFeePercent) / 1 ether,
            supplyBefore + amount
        );

        wrapper.wrap{value: price}(SHARES_SUBJECT, amount);

        assertEq(
            tokenBalanceBefore + amount,
            wrapper.balanceOf(address(this), SHARES_SUBJECT_TOKEN_ID)
        );
        assertEq(
            wrapperSharesBalanceBefore + amount,
            FRIENDTECH.sharesBalance(SHARES_SUBJECT, address(wrapper))
        );
        assertEq(
            supplyBefore + amount,
            FRIENDTECH.sharesSupply(SHARES_SUBJECT)
        );
    }

    function testWrapFuzz(
        uint8 amount,
        bool sendExtraETH,
        uint8 extraETHMultiplier
    ) external {
        vm.assume(amount != 0);
        vm.assume(extraETHMultiplier != 0);

        uint256 price = FRIENDTECH.getBuyPriceAfterFee(SHARES_SUBJECT, amount);
        uint256 tokenBalanceBefore = wrapper.balanceOf(
            address(this),
            SHARES_SUBJECT_TOKEN_ID
        );
        uint256 wrapperSharesBalanceBefore = FRIENDTECH.sharesBalance(
            SHARES_SUBJECT,
            address(wrapper)
        );
        uint256 supplyBefore = FRIENDTECH.sharesSupply(SHARES_SUBJECT);
        uint256 ethBalanceBefore = address(this).balance;

        vm.expectEmit(true, true, true, true, address(wrapper));

        emit TransferSingle(
            address(this),
            address(0),
            address(this),
            SHARES_SUBJECT_TOKEN_ID,
            amount
        );

        wrapper.wrap{
            value: sendExtraETH
                ? price + (uint256(extraETHMultiplier) * 1 ether)
                : price
        }(SHARES_SUBJECT, amount);

        assertEq(
            tokenBalanceBefore + amount,
            wrapper.balanceOf(address(this), SHARES_SUBJECT_TOKEN_ID)
        );
        assertEq(
            wrapperSharesBalanceBefore + amount,
            FRIENDTECH.sharesBalance(SHARES_SUBJECT, address(wrapper))
        );
        assertEq(
            supplyBefore + amount,
            FRIENDTECH.sharesSupply(SHARES_SUBJECT)
        );

        if (sendExtraETH)
            // Balance should only reflect the price being deducted since any extra was returned.
            assertEq(ethBalanceBefore - price, address(this).balance);
    }

    /*//////////////////////////////////////////////////////////////
                             unwrap
    //////////////////////////////////////////////////////////////*/

    function testCannotUnwrapZeroAmount() external {
        vm.expectRevert(WrappedFriendtech.ZeroAmount.selector);

        wrapper.unwrap(SHARES_SUBJECT, 0);
    }

    function testCannotUnwrapZeroSharesSubject() external {
        vm.expectRevert(ERC1155.InsufficientBalance.selector);

        wrapper.unwrap(address(0), 1);
    }

    function testUnwrap() external {
        uint256 amount = 1;

        wrapper.wrap{
            value: FRIENDTECH.getBuyPriceAfterFee(SHARES_SUBJECT, amount)
        }(SHARES_SUBJECT, amount);

        uint256 tokenBalanceBefore = wrapper.balanceOf(
            address(this),
            SHARES_SUBJECT_TOKEN_ID
        );
        uint256 wrapperSharesBalanceBefore = FRIENDTECH.sharesBalance(
            SHARES_SUBJECT,
            address(wrapper)
        );
        uint256 supplyBefore = FRIENDTECH.sharesSupply(SHARES_SUBJECT);
        uint256 ethBalanceBefore = address(this).balance;
        uint256 sellPrice = FRIENDTECH.getSellPriceAfterFee(
            SHARES_SUBJECT,
            amount
        );

        vm.expectEmit(true, true, true, true, address(wrapper));

        emit TransferSingle(
            address(this),
            address(this),
            address(0),
            SHARES_SUBJECT_TOKEN_ID,
            amount
        );

        wrapper.unwrap(SHARES_SUBJECT, amount);

        assertEq(
            tokenBalanceBefore - amount,
            wrapper.balanceOf(address(this), SHARES_SUBJECT_TOKEN_ID)
        );
        assertEq(
            wrapperSharesBalanceBefore - amount,
            FRIENDTECH.sharesBalance(SHARES_SUBJECT, address(wrapper))
        );
        assertEq(
            supplyBefore - amount,
            FRIENDTECH.sharesSupply(SHARES_SUBJECT)
        );
        assertEq(ethBalanceBefore + sellPrice, address(this).balance);
    }

    function testUnwrapFuzz(uint8 amount) external {
        vm.assume(amount != 0);

        wrapper.wrap{
            value: FRIENDTECH.getBuyPriceAfterFee(SHARES_SUBJECT, amount)
        }(SHARES_SUBJECT, amount);

        uint256 tokenBalanceBefore = wrapper.balanceOf(
            address(this),
            SHARES_SUBJECT_TOKEN_ID
        );
        uint256 wrapperSharesBalanceBefore = FRIENDTECH.sharesBalance(
            SHARES_SUBJECT,
            address(wrapper)
        );
        uint256 supplyBefore = FRIENDTECH.sharesSupply(SHARES_SUBJECT);
        uint256 ethBalanceBefore = address(this).balance;
        uint256 sellPrice = FRIENDTECH.getSellPriceAfterFee(
            SHARES_SUBJECT,
            amount
        );

        vm.expectEmit(true, true, true, true, address(wrapper));

        emit TransferSingle(
            address(this),
            address(this),
            address(0),
            SHARES_SUBJECT_TOKEN_ID,
            amount
        );

        wrapper.unwrap(SHARES_SUBJECT, amount);

        assertEq(
            tokenBalanceBefore - amount,
            wrapper.balanceOf(address(this), SHARES_SUBJECT_TOKEN_ID)
        );
        assertEq(
            wrapperSharesBalanceBefore - amount,
            FRIENDTECH.sharesBalance(SHARES_SUBJECT, address(wrapper))
        );
        assertEq(
            supplyBefore - amount,
            FRIENDTECH.sharesSupply(SHARES_SUBJECT)
        );
        assertEq(ethBalanceBefore + sellPrice, address(this).balance);
    }
}
