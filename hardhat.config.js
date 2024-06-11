/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ganache");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("dotenv").config();

module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        bsc_test: {
            url: "https://data-seed-prebsc-1-s1.binance.org:8545",
            accounts: [process.env.PRIVATE_KEY],
        },
        sepolia: {
            url: "https://sepolia.infura.io/v3/45eb256800c24b6c854fb8cd4c73b2c3",
            accounts: [process.env.PRIVATE_KEY],
        },
        bsc_main: {
            url: "https://bsc-dataseed1.binance.org",
            accounts: [process.env.PRIVATE_KEY],
        },
        amoy: {
            url: "https://polygon-amoy.infura.io/v3/45eb256800c24b6c854fb8cd4c73b2c3",
            accounts: [process.env.PRIVATE_KEY],
        },
    },
    mocha: {
        timeout: 1000000000,
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
    polygonscan: {
        apiKey: process.env.POLYGONSCAN_API_KEY
    }
};
