// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBridgeNFT} from "./BridgeNFT.sol";

contract BridgeReceiver is CCIPReceiver, Ownable {
    struct MessageInfo {
        address nftCollection;
        uint64 tokenId;
        address receiver;
    }

    IRouterClient public ROUTER; // get from chainlink
    mapping(uint64 => address) public bridgeSenders;
    mapping(uint64 => mapping(address => address)) public nftCollectionMapping; // (src_chain, nft_address) => nft_address

    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 srcChain,
        address indexed srcCollection,
        uint64 tokenId,
        address indexed dstCollection,
        address receiver
    );

    constructor(address _router) CCIPReceiver(_router) {
        ROUTER = IRouterClient(_router);
    }

    function setBridgeSender(
        uint64 _srcChain,
        address _bridgeSender
    ) external onlyOwner {
        bridgeSenders[_srcChain] = _bridgeSender;
    }

    function addCollection(
        uint64 srcChain,
        address srcCollection,
        address dstCollection
    ) external onlyOwner {
        nftCollectionMapping[srcChain][srcCollection] = dstCollection;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        uint64 srcChain = any2EvmMessage.sourceChainSelector;
        address sender = abi.decode(any2EvmMessage.sender, (address));
        MessageInfo memory data = abi.decode(
            any2EvmMessage.data,
            (MessageInfo)
        );

        if (sender != bridgeSenders[srcChain]) {
            return;
        }

        require(
            nftCollectionMapping[srcChain][data.nftCollection] != address(0),
            "BridgeReceiver: NFT Collection not added on this Bridge"
        );

        IBridgeNFT nft = IBridgeNFT(nftCollectionMapping[srcChain][data.nftCollection]);
        nft.bridgeMint(data.receiver, data.tokenId);

        emit MessageReceived(
            any2EvmMessage.messageId,
            srcChain,
            data.nftCollection,
            data.tokenId,
            nftCollectionMapping[srcChain][data.nftCollection],
            data.receiver
        );
    }
}
