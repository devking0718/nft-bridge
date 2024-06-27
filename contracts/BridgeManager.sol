// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IBridgeNFT} from "./BridgeNFT.sol";
import {CCIPReceiverUpgradeable} from "./CCIPReceiverUpgradeable.sol";

contract BridgeManager is OwnableUpgradeable, CCIPReceiverUpgradeable, IERC721Receiver {
    struct MessageInfo {
        address srcCollection;
        address dstCollection;
        uint64 tokenId;
        address sender;
        address receiver;
    }

    IRouterClient public ROUTER; // get from chainlink
    mapping(uint64 => address) public bridgeManagers; // bridge address on chains
    uint256 public serviceFee; // fee for this service
    mapping(address => bool) public nftCollectionAdded; // if NFT collection is added or not on this chain
    mapping(address => mapping(uint64 => uint64)) public nftBridgedInfo; // (NFT, id) => bridged chain
    mapping(address => mapping(uint64 => address)) public nftCollectionMapping; // (src_nft, dst_chain) => dst_nft

    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        address indexed collectionAddress, // NFT Collection address.
        uint64 tokenId, // NFT Token ID
        uint64 dstChain, // Dst Chain Selector.
        address indexed sender, // NFT sender
        address receiver, // NFT receiver on the destination chain.
        address paymentToken, // 0 for Native Token
        uint256 bridgeFee,
        uint256 serviceFee
    );

    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        address indexed dstCollection,
        uint64 tokenId,
        uint64 srcChain,
        address sender,
        address indexed receiver
    );

    event NFTLocked(
        address indexed owner,
        address indexed collectionAddress,
        uint256 tokenId
    );

    event NFTUnlocked(
        address indexed receiver,
        address indexed collectionAddress,
        uint256 tokenId
    );

    function initialize(address _router) public initializer {
        __Ownable_init();
        __CCIPReceiver_init(_router);
        ROUTER = IRouterClient(_router);
    }

    function lockNFT(address collectionAddress, uint256 tokenId) private {
        IERC721(collectionAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );
        emit NFTLocked(msg.sender, collectionAddress, tokenId);
    }

    function unlockNFT(
        address collectionAddress,
        uint256 tokenId,
        address receiver
    ) private {
        IERC721(collectionAddress).safeTransferFrom(
            address(this),
            receiver,
            tokenId
        );
        emit NFTUnlocked(receiver, collectionAddress, tokenId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function addCollection(
        address srcCollection,
        uint64 dstChain,
        address dstCollection
    ) external onlyOwner {
        nftCollectionAdded[srcCollection] = true;
        nftCollectionMapping[srcCollection][dstChain] = dstCollection;
    }

    function removeCollection(address nftCollection) external onlyOwner {
        nftCollectionAdded[nftCollection] = false;
    }

    function setBridgeManager(
        uint64 _chain,
        address _bridgeManager
    ) external onlyOwner {
        bridgeManagers[_chain] = _bridgeManager;
    }

    function setServiceFee(uint256 _serviceFee) external onlyOwner {
        serviceFee = _serviceFee;
    }

    function bridge(
        address nftCollection,
        uint64 tokenId,
        uint64 dstChain,
        address receiver
    ) external payable returns (bytes32 messageId) {
        require(
            bridgeManagers[dstChain] != address(0),
            "BridgeManager: That chain not allowed for Bridge"
        );
        require(
            nftCollectionAdded[nftCollection],
            "BridgeManager: NFT Collection not added on this Bridge"
        );
        require(
            nftCollectionMapping[nftCollection][dstChain] != address(0),
            "BridgeManager: NFT Collection not allowed on the destination chain"
        );
        require(
            IERC721(nftCollection).ownerOf(tokenId) == msg.sender,
            "BridgeManager: NFT Token not owned by the user"
        );

        MessageInfo memory data = MessageInfo({
            srcCollection: nftCollection,
            dstCollection: nftCollectionMapping[nftCollection][dstChain],
            tokenId: tokenId,
            sender: msg.sender,
            receiver: receiver
        });

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(bridgeManagers[dstChain]), // ABI-encoded receiver address
            data: abi.encode(data),
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000}) // Additional arguments, setting gas limit
            ),
            feeToken: address(0) // Set the feeToken  address, indicating Native Token will be used for bridgeFee
        });

        uint256 bridgeFee = ROUTER.getFee(dstChain, evm2AnyMessage); // Get the fee required to send the message
        require(
            msg.value >= bridgeFee + serviceFee,
            "BridgeManager: Insufficient Fee"
        );

        // Send the message through the router and store the returned message ID
        messageId = ROUTER.ccipSend{value: bridgeFee}(dstChain, evm2AnyMessage);

        // Lock NFT by sending NFT to this
        lockNFT(nftCollection, tokenId);

        uint256 restFee = msg.value - bridgeFee - serviceFee;
        if (restFee > 0) {
            // Refund the rest Fee to the caller
            (bool success, ) = msg.sender.call{value: restFee}("");
            require(success, "BridgeManager: Refund failed");
        }

        nftBridgedInfo[nftCollection][tokenId] = dstChain;

        // Emit an event with message details
        emit MessageSent(
            messageId,
            nftCollection,
            tokenId,
            dstChain,
            msg.sender,
            receiver,
            address(0),
            bridgeFee,
            serviceFee
        );

        // Return the message ID
        return messageId;
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

        if (sender != bridgeManagers[srcChain]) {
            return;
        }

        require(
            nftCollectionAdded[data.dstCollection],
            "BridgeManager: NFT Collection not added on this Bridge"
        );

        require(
            nftCollectionMapping[data.dstCollection][srcChain] ==
                data.srcCollection,
            "BridgeManager: NFT Collection not mapped on this Bridge"
        );

        if (
            nftBridgedInfo[data.dstCollection][data.tokenId] != 0 &&
            IERC721(data.dstCollection).ownerOf(data.tokenId) == address(this)
        ) {
            unlockNFT(data.dstCollection, data.tokenId, data.receiver);
        } else {
            IBridgeNFT nft = IBridgeNFT(data.dstCollection);
            nft.bridgeMint(data.receiver, data.tokenId);
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            data.dstCollection,
            data.tokenId,
            srcChain,
            data.sender,
            data.receiver
        );
    }

    function withdrawBalance(address receiver) external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = receiver.call{value: balance}("");
            require(success, "BridgeManager: Withdraw failed");
        }
    }

    function withdrawNFT(
        address nftCollection,
        uint64 tokenId,
        address receiver
    ) external onlyOwner {
        require(
            IERC721(nftCollection).ownerOf(tokenId) == address(this),
            "BridgeManager: Contract not owned the NFT token"
        );
        IERC721(nftCollection).safeTransferFrom(
            address(this),
            receiver,
            tokenId
        );
    }
}
