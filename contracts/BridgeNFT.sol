//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBridgeNFT {
    event BridgeMinted(address to, uint256 tokenId);
    function bridgeMint(address to, uint256 tokenId) external;
}

contract BridgeNFT is ERC721Enumerable, Ownable, IBridgeNFT {
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

    function bridgeMint(address to, uint256 tokenId) external {
        require(msg.sender == bridgeReceiver, "BridgeNFT: Only Bridge can mint");
        _safeMint(to, tokenId);
        emit BridgeMinted(to, tokenId);
    }
}
