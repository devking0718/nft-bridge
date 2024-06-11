const { ethers, upgrades } = require("hardhat");

const UNISWAP_V2_ROUTER = "0x425141165d3DE9FEC831896C016617a52363b687";

const NFT_BASE_URL = "https://ipfs.io/ipfs/QmV6kA1AedDtbLWB4RZm2gMLjFrifwt4gEmQeWD6t2ywLW/";
const ETH_ROUTER = "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59";
const ETH_SELECTOR = "16015286601757825753";
const MATIC_ROUTER = "0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2";
const MATIC_SELECTOR = "16281711391670634445";
const NFT_NAME = "Ambassadors";
const NFT_SYMBOL = "Ambassadors";

async function check_network() {
    console.log(BINANCE_ROUTER_ADDRESS);
}

async function main() {
    const EG = await ethers.getContractFactory("Teleport");
    console.log("Deploying EG...");
    const contract = await upgrades.deployProxy(EG, [UNISWAP_V2_ROUTER], {
        initializer: "initialize",
        kind: "transparent",
    });
    await contract.deployed();
    console.log("EG:", contract.address);
}

async function upgrade() {
    const EGv2 = await ethers.getContractFactory("EG");
    upgrades.upgradeProxy("0x2764Fd988511C1d4A36E64Ed9F793183803601e2", EGv2);
    const contract = await EGv2.attach(
        "0x2764Fd988511C1d4A36E64Ed9F793183803601e2"
    );
}

async function bridge_sender() {
    const BS = await ethers.getContractFactory("BridgeSender");
    console.log("Deploying BridgeSender...");
    const contract = await BS.deploy(ETH_ROUTER, MATIC_SELECTOR);
    console.log("BridgeSender:", contract.address);
}

async function bridge_receiver() {
    const BR = await ethers.getContractFactory("BridgeReceiver");
    console.log("Deploying BridgeReceiver...");
    const contract = await BR.deploy(MATIC_ROUTER, ETH_SELECTOR);
    console.log("BridgeReceiver:", contract.address);
}

async function bridge_nft() {
    const BN = await ethers.getContractFactory("BridgeNFT");
    console.log("Deploying BridgeNFT...");
    const contract = await BN.deploy(NFT_NAME, NFT_SYMBOL, NFT_BASE_URL);
    console.log("BridgeNFT:", contract.address);
}

// check_network();
// main();

// bridge_sender();
bridge_receiver();
// bridge_nft();