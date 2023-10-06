// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC1155} from "solady/tokens/ERC1155.sol";
import {LibString} from "solady/utils/LibString.sol";

contract FriendWrapper is ERC1155 {
    using LibString for uint256;

    string public constant BASE_URI = "https://prod-api.kosetto.com/users/";

    function uri(uint256 id) public pure override returns (string memory) {
        return string.concat(BASE_URI, id.toString());
    }
}
