//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IBridgeNFT {
    event BridgeMinted(address to, uint256 tokenId);
    function bridgeMint(address to, uint256 tokenId) external;
}

contract BridgeNFT is ERC721Enumerable, Ownable, IBridgeNFT {
    using Strings for uint256;

    string public baseURI;

    address public bridgeReceiver;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseUri
    ) ERC721(name, symbol) {
        baseURI = baseUri;
    }

    function setBridgeReceiver(address _bridgeReceiver) external onlyOwner {
        bridgeReceiver = _bridgeReceiver;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function bridgeMint(address to, uint256 tokenId) public {
        require(
            msg.sender == bridgeReceiver,
            "BridgeNFT: Only Bridge can mint"
        );
        _safeMint(to, tokenId);
        emit BridgeMinted(to, tokenId);
    }

    // Override tokenURI function to append .json
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        // Concatenate the base URI, tokenId, and ".json"
        string memory jsonFile = string(
            abi.encodePacked(baseURI, tokenId.toString(), ".json")
        );
        return jsonFile;
    }
}
