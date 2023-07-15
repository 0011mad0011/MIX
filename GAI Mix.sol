// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUniswapV2Router {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

contract Mixer {
    mapping(address => uint256) private balances;

    event Deposit(address indexed depositor, uint256 amount);
    event Withdraw(address indexed recipient, uint256 amount);

    function deposit() public payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(address payable recipient, uint256 amount) public {
        require(amount > 0, "Invalid amount");
        require(amount <= balances[msg.sender], "Insufficient balance");

        balances[msg.sender] -= amount;
        recipient.transfer(amount);
        emit Withdraw(recipient, amount);
    }
}

contract GuardianAI {
    string private name = "Guardian AI";
    string private symbol = "GAI";
    uint256 private totalSupply = 4000000000; // Total supply of 4 billion tokens
    uint8 private decimals = 18;
    uint256 private halvingInterval = 1 * 365 * 1 days; // Interval between halvings
    uint256 private halvingEndTime = block.timestamp + (365 days * (2140 - 1970));
    uint256 private targetCirculation = 1000000000; // Target circulation of 1 billion coins

    struct Transaction {
        address sender;
        address to;
        uint256 value;
        uint256 timestamp;
    }

    mapping(address => uint256) private balanceOf; // Keeps track of the balance of each address
    mapping(address => Transaction[]) private transactionQueue; // FIFO transaction queue for each address
    uint256 private maxWalletPercentage = 1; // Maximum percentage of tokens that any wallet can hold
    uint256 private maxSellPercentage = 1; // Maximum percentage of tokens that any wallet can sell
    uint256 private feeInMATIC = 5000000000000000000; // Fee amount in MATIC (equivalent to $5)
    address private feeRecipient = 0x9A1eee9eB775021ff120d87D9530D379c96C9326; // Recipient of the fee
    address private uniswapRouterAddress = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; // Uniswap V2 Router address
    uint256 private marketCapThreshold = 1000000000 * 1e18; // Market capitalization threshold of $1 billion
    uint256 private stableDuration = 30 days; // Duration of market capitalization stability
    uint256 private lastMarketCapCheck = block.timestamp;
    uint256 private stableMarketCapDuration;
    mapping(address => bool) private holdersMap;
    address[] private holders;
    uint256 private giveawayAmount = 5000 * 1e18; // Amount to be given away in the giveaway ($5000)
    uint256 private requiredParticipants = 1000; // Minimum number of participants required for the giveaway
    address private giveawayWallet = 0x10AC421092a0bdA2288d315fC55f9545F647D424; // Wallet address for participants to send GAI Tokens
    mapping(address => bool) private giveawayParticipants;
    uint256 private monthlyGiveawayParticipantAmount = 50 * 1e18; // Amount participants need to send to be eligible for the monthly giveaway ($50)

    event Transfer(address indexed from, address indexed to, uint256 value);
    event WalletSelected(address indexed walletOwner, uint256 amount);
    event GiveawayCompleted(uint256 totalParticipants, uint256 totalAmount);

    modifier halving() {
        if (block.timestamp >= halvingEndTime || totalSupply <= targetCirculation) {
            _;
        } else {
            uint256 halvingCount = (block.timestamp - halvingEndTime) / halvingInterval;
            uint256 halvingFactor = 2 ** halvingCount;
            totalSupply /= halvingFactor;
            _;
            totalSupply *= halvingFactor;
        }
    }

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        holdersMap[msg.sender] = true;
        holders.push(msg.sender);
    }

    function executeTransaction(address _to, uint256 _value) external halving {
        require(balanceOf[msg.sender] >= _value, "Insufficient balance.");
        require(
            balanceOf[_to] + _value <= totalSupply * maxWalletPercentage / 100 ||
            isExcludedFromMaxWalletLimit(_to), // Check if the recipient is excluded from the maximum wallet limit
            "The recipient's wallet would exceed the maximum percentage of tokens allowed."
        );

        Transaction memory newTransaction = Transaction(msg.sender, _to, _value, block.timestamp);
        transactionQueue[msg.sender].push(newTransaction);

        emit Transfer(msg.sender, _to, _value);
    }

    function processTransaction() external halving {
        Transaction[] storage transactions = transactionQueue[msg.sender];
        require(transactions.length > 0, "No pending transactions.");

        Transaction storage nextTransaction = transactions[0];
        require(block.timestamp >= nextTransaction.timestamp, "Transaction cannot be processed yet.");

        uint256 feeAmount = isExcludedFromFee(nextTransaction.sender) ? 0 : calculateFeeAmount(nextTransaction.value);
        require(balanceOf[nextTransaction.sender] >= nextTransaction.value + feeAmount, "Insufficient balance to pay the fee.");

        balanceOf[nextTransaction.sender] -= nextTransaction.value + feeAmount;
        balanceOf[nextTransaction.to] += nextTransaction.value;
        balanceOf[feeRecipient] += feeAmount;

        emit Transfer(nextTransaction.sender, nextTransaction.to, nextTransaction.value);

        // Remove the processed transaction from the queue
        for (uint256 i = 0; i < transactions.length - 1; i++) {
            transactions[i] = transactions[i + 1];
        }
        transactions.pop();
    }

    function setMaxWalletPercentage(uint256 _maxWalletPercentage) external {
        require(msg.sender == feeRecipient, "You are not authorized to set the maximum wallet percentage.");
        maxWalletPercentage = _maxWalletPercentage;
    }

    function setMaxSellPercentage(uint256 _maxSellPercentage) external {
        require(msg.sender == feeRecipient, "You are not authorized to set the maximum sell percentage.");
        maxSellPercentage = _maxSellPercentage;
    }

    function calculateFeeAmount(uint256 _value) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouterAddress;
        path[1] = address(this); // GAI Token address
        uint256[] memory amounts = IUniswapV2Router(uniswapRouterAddress).getAmountsOut(feeInMATIC, path);
        uint256 feeAmount = (_value * amounts[1]) / 1e18;
        return feeAmount;
    }

    function getGasPrice() external view returns (uint256) {
        return tx.gasprice;
    }

    function checkMarketCapStability() external {
        require(balanceOf[giveawayWallet] >= 200 * 5000 * 1e18, "Insufficient funds in the giveaway wallet.");
        require(block.timestamp >= lastMarketCapCheck + stableDuration, "Market capitalization stability duration not reached.");

        uint256 currentMarketCap = balanceOf[giveawayWallet];
        require(currentMarketCap >= marketCapThreshold, "Market capitalization threshold not reached.");

        stableMarketCapDuration += block.timestamp - lastMarketCapCheck;
        lastMarketCapCheck = block.timestamp;

        if (stableMarketCapDuration >= stableDuration) {
            selectRandomWallets();
            selectRandomWallets2();
            selectRandomWallets3();
            selectRandomWallets4();
            selectRandomWallets5();
            selectRandomWallets6();
        }
    }

    function selectRandomWallets() private {
        uint256 totalHolders = getTotalHoldersCount();
        uint256[] memory selectedIndexes = generateRandomIndexes(totalHolders, requiredParticipants);
        address[] memory allHolders = getAllHolders();

        for (uint256 i = 0; i < selectedIndexes.length; i++) {
            address selectedWallet = allHolders[selectedIndexes[i]];
            balanceOf[giveawayWallet] -= giveawayAmount;
            balanceOf[selectedWallet] += giveawayAmount;

            emit WalletSelected(selectedWallet, giveawayAmount);
            emit Transfer(giveawayWallet, selectedWallet, giveawayAmount);
        }

        emit GiveawayCompleted(requiredParticipants, giveawayAmount);

        stableMarketCapDuration = 0;
    }

    function selectRandomWallets2() private {
        uint256 totalHolders = getTotalHoldersCount();
        uint256[] memory selectedIndexes = generateRandomIndexes(totalHolders, requiredParticipants);
        address[] memory allHolders = getAllHolders();

        for (uint256 i = 0; i < selectedIndexes.length; i++) {
            address selectedWallet = allHolders[selectedIndexes[i]];
            balanceOf[giveawayWallet] -= giveawayAmount;
            balanceOf[selectedWallet] += giveawayAmount;

            emit WalletSelected(selectedWallet, giveawayAmount);
            emit Transfer(giveawayWallet, selectedWallet, giveawayAmount);
        }

        emit GiveawayCompleted(requiredParticipants, giveawayAmount);

        stableMarketCapDuration = 0;
    }

    function selectRandomWallets3() private {
        uint256 totalHolders = getTotalHoldersCount();
        uint256[] memory selectedIndexes = generateRandomIndexes(totalHolders, requiredParticipants);
        address[] memory allHolders = getAllHolders();

        for (uint256 i = 0; i < selectedIndexes.length; i++) {
            address selectedWallet = allHolders[selectedIndexes[i]];
            balanceOf[giveawayWallet] -= giveawayAmount;
            balanceOf[selectedWallet] += giveawayAmount;

            emit WalletSelected(selectedWallet, giveawayAmount);
            emit Transfer(giveawayWallet, selectedWallet, giveawayAmount);
        }

        emit GiveawayCompleted(requiredParticipants, giveawayAmount);

        stableMarketCapDuration = 0;
    }

    function selectRandomWallets4() private {
        uint256 totalHolders = getTotalHoldersCount();
        uint256[] memory selectedIndexes = generateRandomIndexes(totalHolders, requiredParticipants);
        address[] memory allHolders = getAllHolders();

        for (uint256 i = 0; i < selectedIndexes.length; i++) {
            address selectedWallet = allHolders[selectedIndexes[i]];
            balanceOf[giveawayWallet] -= giveawayAmount;
            balanceOf[selectedWallet] += giveawayAmount;

            emit WalletSelected(selectedWallet, giveawayAmount);
            emit Transfer(giveawayWallet, selectedWallet, giveawayAmount);
        }

        emit GiveawayCompleted(requiredParticipants, giveawayAmount);

        stableMarketCapDuration = 0;
    }

    function selectRandomWallets5() private {
        uint256 totalHolders = getTotalHoldersCount();
        uint256[] memory selectedIndexes = generateRandomIndexes(totalHolders, requiredParticipants);
        address[] memory allHolders = getAllHolders();

        for (uint256 i = 0; i < selectedIndexes.length; i++) {
            address selectedWallet = allHolders[selectedIndexes[i]];
            balanceOf[giveawayWallet] -= giveawayAmount;
            balanceOf[selectedWallet] += giveawayAmount;

            emit WalletSelected(selectedWallet, giveawayAmount);
            emit Transfer(giveawayWallet, selectedWallet, giveawayAmount);
        }

        emit GiveawayCompleted(requiredParticipants, giveawayAmount);

        stableMarketCapDuration = 0;
    }

    function selectRandomWallets6() private {
        uint256 totalHolders = getTotalHoldersCount();
        uint256[] memory selectedIndexes = generateRandomIndexes(totalHolders, requiredParticipants);
        address[] memory allHolders = getAllHolders();

        require(giveawayAmount * requiredParticipants <= balanceOf[giveawayWallet], "Insufficient funds in the giveaway wallet.");

        for (uint256 i = 0; i < selectedIndexes.length; i++) {
            address selectedWallet = allHolders[selectedIndexes[i]];
            balanceOf[giveawayWallet] -= giveawayAmount;
            balanceOf[selectedWallet] += giveawayAmount;
            giveawayParticipants[selectedWallet] = true;

            emit WalletSelected(selectedWallet, giveawayAmount);
            emit Transfer(giveawayWallet, selectedWallet, giveawayAmount);
        }

        emit GiveawayCompleted(requiredParticipants, giveawayAmount);
        stableMarketCapDuration = 0;
    }

    function getTotalHoldersCount() private view returns (uint256) {
        return holders.length;
    }

    function getAllHolders() private view returns (address[] memory) {
        return holders;
    }

    function generateRandomIndexes(uint256 total, uint256 count) private view returns (uint256[] memory) {
        require(count <= total, "Cannot generate more indexes than the total");

        uint256[] memory indexes = new uint256[](count);
        uint256 lastIndex = total - 1;

        // Generate random indexes using Fisher-Yates shuffle algorithm
        for (uint256 i = 0; i < count; i++) {
            uint256 randomIndex = i + (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, i))) % (lastIndex - i + 1));
            indexes[i] = randomIndex;
        }

        return indexes;
    }

    function checkGiveawayAmount() external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouterAddress;
        path[1] = address(this); // GAI Token address
        uint256[] memory amounts = IUniswapV2Router(uniswapRouterAddress).getAmountsOut(giveawayAmount, path);
        return amounts[1]; // Return the estimated $ value of the giveaway amount
    }

    function isExcludedFromFee(address _wallet) private pure returns (bool) {
        return (
            _wallet == 0x9A1eee9eB775021ff120d87D9530D379c96C9326 ||
            _wallet == 0x10AC421092a0bdA2288d315fC55f9545F647D424 ||
            _wallet == 0xE0B942cF1CCea905121D88F22286d9028abb0308
        );
    }

    function isExcludedFromMaxWalletLimit(address _wallet) private pure returns (bool) {
        return (
            _wallet == 0x9A1eee9eB775021ff120d87D9530D379c96C9326 ||
            _wallet == 0x10AC421092a0bdA2288d315fC55f9545F647D424 ||
            _wallet == 0xE0B942cF1CCea905121D88F22286d9028abb0308
        );
    }
}
