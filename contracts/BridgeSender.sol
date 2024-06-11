// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BridgeSender is Ownable, IERC721Receiver {
    struct MessageInfo {
        address nftCollection;
        uint64 tokenId;
        address receiver;
    }

    IRouterClient public ROUTER; // get from chainlink
    uint64 public DEST_CHAIN; // get from chainlink

    address public bridgeReceiver; // address of brdigeReciver on dest chain
    uint256 public serviceFee; // fee for this service

    mapping(address => bool) public nftCollectionAdded;

    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        address indexed collectionAddress, // NFT Collection address.
        uint64 tokenId, // NFT Token ID
        address indexed receiver, // The address of the NFT receiver on the destination chain.
        uint256 bridgeFee,
        uint256 serviceFee
    );

    event NFTLocked(
        address indexed owner,
        address indexed collectionAddress,
        uint256 tokenId
    );

    constructor(address _router, uint64 _destChain) {
        ROUTER = IRouterClient(_router);
        DEST_CHAIN = _destChain;
    }

    function lockNFT(address collectionAddress, uint256 tokenId) private {
        IERC721(collectionAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );
        emit NFTLocked(msg.sender, collectionAddress, tokenId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function addCollection(address nftCollection) external onlyOwner {
        nftCollectionAdded[nftCollection] = true;
    }

    function removeCollection(address nftCollection) external onlyOwner {
        nftCollectionAdded[nftCollection] = false;
    }

    function setBridgeReceiver(address _bridgeReceiver) external onlyOwner {
        bridgeReceiver = _bridgeReceiver;
    }

    function setServiceFee(uint256 _serviceFee) external onlyOwner {
        serviceFee = _serviceFee;
    }

    function withdrawBalance(address receiver) external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = receiver.call{value: balance}("");
            require(success, "BridgeSender: Withdraw failed");
        }
    }

    function bridge(
        address nftCollection,
        uint64 tokenId,
        address receiver
    ) external payable returns (bytes32 messageId) {
        require(
            nftCollectionAdded[nftCollection],
            "BridgeSender: NFT Collection not added on this Bridge"
        );
        require(
            IERC721(nftCollection).ownerOf(tokenId) == msg.sender,
            "BridgeSender: NFT Token not owned by the user"
        );

        MessageInfo memory data = MessageInfo({
            nftCollection: nftCollection,
            tokenId: tokenId,
            receiver: receiver
        });

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(bridgeReceiver), // ABI-encoded receiver address
            data: abi.encode(data),
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000}) // Additional arguments, setting gas limit
            ),
            feeToken: address(0) // Set the feeToken  address, indicating Native Token will be used for bridgeFee
        });

        uint256 bridgeFee = ROUTER.getFee(DEST_CHAIN, evm2AnyMessage); // Get the fee required to send the message
        require(
            msg.value >= bridgeFee + serviceFee,
            "BridgeSender: Insufficient Fee"
        );

        // Send the message through the router and store the returned message ID
        messageId = ROUTER.ccipSend{value: bridgeFee}(
            DEST_CHAIN,
            evm2AnyMessage
        );

        // Lock NFT by sending NFT to this
        lockNFT(nftCollection, tokenId);

        uint256 restFee = msg.value - bridgeFee - serviceFee;
        if (restFee > 0) {
            // Refund the rest Fee to the caller
            (bool success, ) = msg.sender.call{value: restFee}("");
            require(success, "BridgeSender: Refund failed");
        }

        // Emit an event with message details
        emit MessageSent(
            messageId,
            nftCollection,
            tokenId,
            receiver,
            bridgeFee,
            serviceFee
        );

        // Return the message ID
        return messageId;
    }
}