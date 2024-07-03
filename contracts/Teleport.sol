// Copyright (c) 2024 Teleport Global Ltd. All rights reserved.
// Teleport licenses this file to you under the MIT license.

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// helper methods for discovering LP pair addresses
library PairHelper {
    bytes private constant token0Selector =
        abi.encodeWithSelector(IUniswapV2Pair.token0.selector);
    bytes private constant token1Selector =
        abi.encodeWithSelector(IUniswapV2Pair.token1.selector);

    function token0(address pair) internal view returns (address) {
        return token(pair, token0Selector);
    }

    function token1(address pair) internal view returns (address) {
        return token(pair, token1Selector);
    }

    function token(
        address pair,
        bytes memory selector
    ) private view returns (address) {
        // Do not check if pair is not a contract to avoid warning in transaction log
        if (!isContract(pair)) return address(0);

        (bool success, bytes memory data) = pair.staticcall(selector);

        if (success && data.length >= 32) {
            return abi.decode(data, (address));
        }

        return address(0);
    }

    function isContract(address account) private view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            codehash := extcodehash(account)
        }

        return (codehash != accountHash && codehash != 0x0);
    }
}

contract Teleport is IERC20Upgradeable, OwnableUpgradeable {
    using PairHelper for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct TransferDetails {
        uint112 balance0; // balance of token0
        uint112 balance1; // balance of token1
        uint32 blockNumber; // block number of  transfer
        address to; // receive address of transfer
        address origin; // submitter address of transfer
    }

    uint256 public totalSupply; // total supply

    uint8 public constant decimals = 18; // decimals of token

    string public constant name = "Teleport"; // name of token
    string public constant symbol = "TLPT"; // symbol of token

    IUniswapV2Router02 public uniswapV2Router; // uniswap router
    address public uniswapV2Pair; // uniswap pair

    uint256 public buyFee; // buy fee
    uint256 public sellFee; // sell fee
    uint256 public transferFee; // transfer fee

    mapping(address => uint256) private _balances; // balances of token

    mapping(address => mapping(address => uint256)) private _allowances; // allowances of token

    uint256 private constant MAX = ~uint256(0); // max uint256

    bool private _checkingTokens; // checking tokens flag

    mapping(address => bool) public whiteList; // white list => excluded from fee
    mapping(address => bool) public blackList; // black list => disable _transfer

    bool private _inSwap;
    bool public autoSellTax;

    modifier tokenCheck() {
        require(!_checkingTokens);
        _checkingTokens = true;
        _;
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _checkingTokens = false;
    }

    modifier lockTheSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }
    
    event TradingEnabled();
    event RouterAddressUpdated(address prevAddress, address newAddress);
    event MarketingWalletUpdated(address prevAddress, address newAddress);
    event MarketingWalletFeeUpdated(uint256 prevFee, uint256 newFee);
    event LiquidityWalletUpdated(address prevAddress, address newAddress);
    event LiquidityWalletFeeUpdated(uint256 prevFee, uint256 newFee);
    event TechWalletUpdated(address prevAddress, address newAddress);
    event TechWalletFeeUpdated(uint256 prevFee, uint256 newFee);
    event DonationsWalletUpdated(address prevAddress, address newAddress);
    event DonationsWalletFeeUpdated(uint256 prevFee, uint256 newFee);
    event StakingRewardsWalletUpdated(address prevAddress, address newAddress);
    event StakingRewardsWalletFeeUpdated(uint256 prevFee, uint256 newFee);

    event BuyFeeUpdated(uint256 prevValue, uint256 newValue);
    event SellFeeUpdated(uint256 prevValue, uint256 newValue);
    event TransferFeeUpdated(uint256 prevValue, uint256 newValue);

    event AddClientsToWhiteList(address[] account);
    event RemoveClientsFromWhiteList(address[] account);

    event WithdrawTokens(uint256 amount);
    event WithdrawAlienTokens(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event WithdrawNativeTokens(address indexed to, uint256 amount);
    event MaxTransactionAmountUpdated(uint256 prevValue, uint256 nextValue);
    event MaxTransactionCoolDownAmountUpdated(
        uint256 prevValue,
        uint256 nextValue
    );
    event AddClientsToBlackList(address[] accounts);
    event RemoveClientsFromBlackList(address[] accounts);

    /**
     * @param _routerAddress BSC MAIN 0x10ed43c718714eb63d5aa57b78b54704e256024e
     * @param _routerAddress BSC TEST 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
     **/
    function initialize(address _routerAddress) external initializer {
        require(
            _routerAddress != address(0),
            "Teleport: routerAddress should not be the zero address"
        );

        __Ownable_init();

        totalSupply = 10 ** 6 * 10 ** decimals; // total supply of token (6 billion)

        buyFee = 5; // 5%
        sellFee = 5; // 5%
        transferFee = 0; // 0%

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            _routerAddress
        );
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;

        _balances[msg.sender] = totalSupply;

        whiteList[owner()] = true;
        whiteList[address(this)] = true;

        emit Transfer(address(0), _msgSender(), totalSupply);
    }

    /**
     * @dev Function to receive ETH when msg.data is empty
     * @dev Receives ETH from uniswapV2Router when swapping
     **/
    receive() external payable {}

    /**
     * @dev Fallback function to receive ETH when msg.data is not empty
     **/
    fallback() external payable {}

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function allowance(
        address from,
        address spender
    ) external view override returns (uint256) {
        return _allowances[from][spender];
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        uint256 balance0 = _balanceOf(account);
        return balance0;
    }

    /**
     * @param accounts list of clients to whitelist so they do not pay tax on buy or sell
     *
     * @dev exclude a wallet from paying tax
     **/
    function addClientsToWhiteList(
        address[] calldata accounts
    ) external onlyOwner {
        for (uint256 i; i < accounts.length; i++) {
            require(
                accounts[i] != address(0),
                "Teleport: Zero address can't be added to whitelist"
            );
        }

        for (uint256 i; i < accounts.length; i++) {
            if (!whiteList[accounts[i]]) {
                whiteList[accounts[i]] = true;
            }
        }

        emit AddClientsToWhiteList(accounts);
    }

    /**
     * @param accounts list of clients to remove from whitelist so they start paying tax on buy or sell
     *
     * @dev include a wallet to pay tax
     **/
    function removeClientsFromWhiteList(
        address[] calldata accounts
    ) external onlyOwner {
        for (uint256 i; i < accounts.length; i++) {
            if (whiteList[accounts[i]]) {
                whiteList[accounts[i]] = false;
            }
        }

        emit RemoveClientsFromWhiteList(accounts);
    }

    /**
     * @param accounts list of clients to add to blacklist (trading not allowed)
     *
     * @dev add clients to blacklist
     **/
    function addClientsToBlackList(
        address[] calldata accounts
    ) external onlyOwner {
        for (uint256 i; i < accounts.length; i++) {
            require(
                accounts[i] != address(0),
                "Teleport: Zero address can't be added to blacklist"
            );
        }

        for (uint256 i; i < accounts.length; i++) {
            if (!blackList[accounts[i]]) {
                blackList[accounts[i]] = true;
            }
        }

        emit AddClientsToBlackList(accounts);
    }

    /**
     * @param accounts list to remove from blacklist
     *
     * @dev remove accounts from blacklist
     **/
    function removeClientsFromBlackList(
        address[] calldata accounts
    ) external onlyOwner {
        for (uint256 i; i < accounts.length; i++) {
            if (blackList[accounts[i]]) {
                blackList[accounts[i]] = false;
            }
        }

        emit RemoveClientsFromBlackList(accounts);
    }

    /**
     * @param routerAddress SWAP router address
     *
     * @dev set swap router address
     **/
    function setRouterAddress(address routerAddress) external onlyOwner {
        require(
            routerAddress != address(0),
            "routerAddress should not be the zero address"
        );

        address prevAddress = address(uniswapV2Router);
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(routerAddress);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).getPair(
            address(this),
            _uniswapV2Router.WETH()
        );

        uniswapV2Router = _uniswapV2Router;
        emit RouterAddressUpdated(prevAddress, routerAddress);
    }

    /**
     * @param _auto Flag if auto sell tax or not
     *
     * @dev Set to auto sell tax or not
     **/
    function setAutoSellTax(bool _auto) external onlyOwner {
        autoSellTax = _auto;
    }

    /**
     * @param _amount amount
     *
     * @dev calculate buy fee
     **/
    function calculateBuyFee(uint256 _amount) private view returns (uint256) {
        return (_amount * buyFee) / 100;
    }

    /**
     * @param _amount amount
     *
     * @dev calculate sell fee
     **/
    function calculateSellFee(uint256 _amount) private view returns (uint256) {
        return (_amount * sellFee) / 100;
    }

    /**
     * @param _amount amount
     *
     * @dev calculate transfer fee
     **/
    function calculateTransferFee(
        uint256 _amount
    ) private view returns (uint256) {
        return (_amount * transferFee) / 100;
    }

    /**
     * @param _buyFee. Buy fee percent (0% ~ 99%)
     *
     **/
    function setBuyFee(uint256 _buyFee) external onlyOwner {
        require(_buyFee < 100, "Teleport: buyFeeRate should be less than 100%");

        uint256 prevValue = buyFee;
        buyFee = _buyFee;
        emit BuyFeeUpdated(prevValue, buyFee);
    }

    /**
     * @param _sellFee. Sell fee percent (0% ~ 99%)
     *
     **/
    function setSellFee(uint256 _sellFee) external onlyOwner {
        require(_sellFee < 100, "Teleport: sellFeeRate should be less than 100%");

        uint256 prevValue = sellFee;
        sellFee = _sellFee;
        emit SellFeeUpdated(prevValue, sellFee);
    }

    /**
     * @param _transferFee. Transfer fee pcercent (0% ~ 99%)
     *
     **/
    function setTransferFee(uint256 _transferFee) external onlyOwner {
        require(
            _transferFee < 100,
            "Teleport: transferFeeRate should be less than 100%"
        );

        uint256 prevValue = transferFee;
        transferFee = _transferFee;
        emit TransferFeeUpdated(prevValue, transferFee);
    }

    function _balanceOf(address account) private view returns (uint256) {
        return _balances[account];
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function isTeleportPair(address _pair) public view returns (bool) {
        bool _result;
        if (_pair.token0() != address(0) && _pair.token1() != address(0)) {
            if (
                _pair.token0() == address(this) ||
                _pair.token1() == address(this)
            ) {
                _result = true;
            }
        }
        return _result;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(
            !blackList[from] || to == owner(), // allow blacklisted user to send token only to contract owner
            "Teleport: transfer from the blacklist address is not allowed"
        );
        require(
            !blackList[to],
            "Teleport: transfer to the blacklist address is not allowed"
        );
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "ERC20: Transfer amount must be greater than zero");
        require(
            _balances[from] >= amount,
            "ERC20: tokens balance is insufficient"
        );
        require(from != to, "ERC20: Transfer to and from address are the same");
        require(
            !inTokenCheck(),
            "Invalid reentrancy from token0/token1 balanceOf check"
        );

        uint256 takeFee = 0;

        bool _isNotExcludeFee = !(whiteList[from] || whiteList[to]);

        bool _isBuy = isTeleportPair(from);
        bool _isSell = isTeleportPair(to);
        if (_isNotExcludeFee) {
            if (_isBuy) {
                // liquidity ( buy / sell ) fee
                takeFee = calculateBuyFee(amount);
            } else if (_isSell) {
                // liquidity ( buy / sell ) fee
                takeFee = calculateSellFee(amount);
            } else {
                // transfer fee
                takeFee = calculateTransferFee(amount);
            }

            uint256 swapAmount = min(_balanceOf(address(this)), amount);
            if (autoSellTax && swapAmount > 0 && !_inSwap && _isSell) {
                swapTokensForETH(swapAmount);
            }
        }
        _tokenTransfer(from, to, amount, takeFee);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    /**
     * @param amount amount
     *
     * @dev swap tax token on contract to ETH, add this ETH to contract balance
     */
    function swapTokensForETH(uint256 amount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), amount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @param sender sender
     * @param recipient recipient
     * @param amount amount
     * @param takeFee fee
     *
     * @dev update balances of sender and receiver, add fee to contract balance
     **/
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        uint256 takeFee
    ) private {
        uint256 senderBefore = _balances[sender];
        uint256 senderAfter = senderBefore - amount;
        _balances[sender] = senderAfter;

        uint256 tTransferAmount = amount;

        if (takeFee > 0) {
            _balances[address(this)] = _balances[address(this)] + takeFee;
            tTransferAmount = amount - takeFee;
        }

        uint256 recipientBefore = _balances[recipient];
        uint256 recipientAfter = recipientBefore + tTransferAmount;
        _balances[recipient] = recipientAfter;

        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
     * @param token token address
     * @param to receive address
     * @param amount token amount
     *
     * @dev Withdraw any tokens that are sent to the contract address
     **/
    function withdrawTokens(
        address token,
        address payable to,
        uint256 amount
    ) external onlyOwner {
        require(
            token != address(0),
            "Teleport: The zero address should not be a token."
        );
        require(
            to != address(0),
            "Teleport: The zero address should not be a transfer address."
        );

        require(amount > 0, "Teleport: Amount should be a postive number.");
        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "Teleport: Out of balance."
        );

        IERC20Upgradeable(token).safeTransfer(to, amount);

        emit WithdrawAlienTokens(token, to, amount);
    }

    /**
     * @param to receive address
     * @param amount token amount
     *
     * @dev You can withdraw native tokens (BNB) accumulated in the contract address
     **/
    function withdrawNativeTokens(
        address payable to,
        uint256 amount
    ) external onlyOwner {
        require(
            to != address(0),
            "Teleport: The zero address should not be a transfer address."
        );
        require(amount > 0, "Teleport: Amount should be a postive number.");
        require(
            address(this).balance >= amount,
            "Teleport: Out of native token balance."
        );

        (bool success, ) = (to).call{value: amount}("");
        require(success, "Teleport: Withdraw failed");

        emit WithdrawNativeTokens(to, amount);
    }

    function inTokenCheck() private view returns (bool) {
        return _checkingTokens;
    }
}