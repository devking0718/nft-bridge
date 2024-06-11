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
    uint64 public SRC_CHAIN; // get from chainlink

    address public bridgeSender;

    mapping(address => address) public nftCollectionMapping;

    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        address indexed srcCollection,
        uint64 tokenId,
        address indexed dstCollection,
        address receiver
    );

    constructor(address _router, uint64 _srcChain) CCIPReceiver(_router) {
        ROUTER = IRouterClient(_router);
        SRC_CHAIN = _srcChain;
    }

    function setBridgeSender(address _bridgeSender) external onlyOwner {
        bridgeSender = _bridgeSender;
    }

    function addCollection(
        address srcCollection,
        address dstCollection
    ) external onlyOwner {
        nftCollectionMapping[srcCollection] = dstCollection;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        address sender = abi.decode(any2EvmMessage.sender, (address));
        MessageInfo memory data = abi.decode(
            any2EvmMessage.data,
            (MessageInfo)
        );

        if (
            any2EvmMessage.sourceChainSelector != SRC_CHAIN ||
            sender != bridgeSender
        ) {
            return;
        }

        require(
            nftCollectionMapping[data.nftCollection] != address(0),
            "BridgeReceiver: NFT Collection not added on this Bridge"
        );

        IBridgeNFT nft = IBridgeNFT(nftCollectionMapping[data.nftCollection]);
        nft.bridgeMint(data.receiver, data.tokenId);

        emit MessageReceived(
            any2EvmMessage.messageId,
            data.nftCollection,
            data.tokenId,
            nftCollectionMapping[data.nftCollection],
            data.receiver
        );
    }
}
