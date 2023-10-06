// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC1155} from "solady/tokens/ERC1155.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IFriendtechSharesV1 {
    function getBuyPriceAfterFee(
        address sharesSubject,
        uint256 amount
    ) external view returns (uint256);

    function getSellPriceAfterFee(
        address sharesSubject,
        uint256 amount
    ) external view returns (uint256);

    function buyShares(address sharesSubject, uint256 amount) external payable;

    function sellShares(address sharesSubject, uint256 amount) external;
}

contract FriendWrapper is ERC1155 {
    using LibString for uint256;
    using SafeTransferLib for address;

    IFriendtechSharesV1 public constant FRIENDTECH =
        IFriendtechSharesV1(0xCF205808Ed36593aa40a44F10c7f7C2F67d4A4d4);
    string public constant BASE_URI = "https://prod-api.kosetto.com/users/";

    function uri(uint256 id) public pure override returns (string memory) {
        return string.concat(BASE_URI, id.toString());
    }

    /**
     * @notice Mints wrapped FT shares.
     * @dev    Follows the checks-effects-interactions pattern to prevent reentrancy.
     * @dev    Emits the `TransferSingle` event as a result of calling `_mint`.
     * @param  sharesSubject  address  Friendtech user address.
     * @param  amount         uint256  Shares amount.
     */
    function wrap(address sharesSubject, uint256 amount) external payable {
        // The token ID is the uint256-casted `sharesSubject` address.
        _mint(msg.sender, uint256(uint160(sharesSubject)), amount, "");

        uint256 price = FRIENDTECH.getBuyPriceAfterFee(sharesSubject, amount);

        // Throws if `msg.value` is insufficient since the contract doesn't (intentionally) maintain an ETH balance.
        FRIENDTECH.buyShares{value: price}(sharesSubject, amount);

        if (msg.value > price) {
            // Will not underflow since `msg.value` is greater than `price`.
            unchecked {
                msg.sender.safeTransferETH(msg.value - price);
            }
        }
    }
}
