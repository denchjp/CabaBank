// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * CabaBank (Owner-only)
 * - Decimal balances via string ("1000.50")
 * - Decimal interest via percent string ("0.8" = 0.8%)
 * - Fixed-point math (1e18 precision)
 * - Batch interest for active members
 * - Manual interest & payout
 * - Batch payout
 * - Editable member names
 * - Per-member history + CSV-friendly events
 */

contract CabaBank {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner allowed");
        _;
    }

    modifier onlyActive(address member) {
        require(isActiveMember[member], "Member is not active");
        _;
    }

    // Member registry
    mapping(address => string) public memberNames;
    mapping(address => bool) public isActiveMember;
    address[] public allMembers;

    // Global interest per currency (fixed-point fraction)
    mapping(string => uint256) public globalInterestFP;

    struct Account {
        uint256 balanceFP; // fixed-point balance (1e18 = 1 unit)
    }

    mapping(address => mapping(string => Account)) public accounts;

    enum ActionType {
        INIT,
        DEPOSIT,
        WITHDRAW,
        INTEREST_APPLIED,
        MANUAL_INTEREST,
        PAYOUT,
        ADMIN_OVERRIDE
    }

    struct HistoryEntry {
        string currency;
        ActionType action;
        uint256 amountFP;
        uint256 balanceAfterFP;
        uint256 timestamp;
        string remarks;
    }

    mapping(address => mapping(uint256 => HistoryEntry)) public history;
    mapping(address => uint256) public historyCount;

    event LedgerEvent(
        address indexed member,
        string currency,
        ActionType action,
        uint256 amountFP,
        uint256 balanceAfterFP,
        uint256 interestFP,
        uint256 timestamp,
        string remarks
    );

    // -------------------------
    // STRING PARSERS
    // -------------------------

    // Parse decimal amount string ("1000.50") into fixed-point (1e18 precision)
    function _stringToFP(string memory amountStr) internal pure returns (uint256) {
        bytes memory b = bytes(amountStr);
        uint256 intPart = 0;
        uint256 fracPart = 0;
        uint256 fracDigits = 0;
        bool hasDecimal = false;

        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];

            if (c == ".") {
                require(!hasDecimal, "Multiple decimals");
                hasDecimal = true;
                continue;
            }

            require(c >= "0" && c <= "9", "Invalid character");

            if (!hasDecimal) {
                intPart = intPart * 10 + (uint8(c) - 48);
            } else {
                require(fracDigits < 18, "Too many decimal places");
                fracPart = fracPart * 10 + (uint8(c) - 48);
                fracDigits++;
            }
        }

        uint256 scaledFrac = fracPart * (10 ** (18 - fracDigits));
        return intPart * 1e18 + scaledFrac;
    }

    // Parse percent string ("0.8") into fixed-point fraction (0.8% = 0.008)
    function _stringPercentToFP(string memory percentStr)
        internal
        pure
        returns (uint256)
    {
        bytes memory b = bytes(percentStr);
        uint256 intPart = 0;
        uint256 fracPart = 0;
        uint256 fracDigits = 0;
        bool hasDecimal = false;

        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];

            if (c == ".") {
                require(!hasDecimal, "Multiple decimals");
                hasDecimal = true;
                continue;
            }

            require(c >= "0" && c <= "9", "Invalid character");

            if (!hasDecimal) {
                intPart = intPart * 10 + (uint8(c) - 48);
            } else {
                require(fracDigits < 18, "Too many decimal places");
                fracPart = fracPart * 10 + (uint8(c) - 48);
                fracDigits++;
            }
        }

        // Convert "0.8" → 0.8 * 1e18
        uint256 scaledFrac = fracPart * (10 ** (18 - fracDigits));
        uint256 percentFP = intPart * 1e18 + scaledFrac;

        return percentFP;
    }

    // -------------------------
    // Internal logging
    // -------------------------

    function _log(
        address member,
        string memory currency,
        ActionType action,
        uint256 amountFP,
        uint256 balanceAfterFP,
        uint256 interestFP,
        string memory remarks
    ) internal {
        uint256 idx = historyCount[member];
        history[member][idx] = HistoryEntry({
            currency: currency,
            action: action,
            amountFP: amountFP,
            balanceAfterFP: balanceAfterFP,
            timestamp: block.timestamp,
            remarks: remarks
        });
        historyCount[member]++;

        emit LedgerEvent(
            member,
            currency,
            action,
            amountFP,
            balanceAfterFP,
            interestFP,
            block.timestamp,
            remarks
        );
    }

    // -------------------------
    // Member management
    // -------------------------

    function registerMember(
        address member,
        string calldata name,
        bool active
    ) external onlyOwner {
        require(bytes(memberNames[member]).length == 0, "Already registered");
        memberNames[member] = name;
        isActiveMember[member] = active;
        allMembers.push(member);
    }

    function updateMemberName(address member, string calldata newName)
        external
        onlyOwner
    {
        require(bytes(memberNames[member]).length != 0, "Not registered");
        memberNames[member] = newName;
    }

    function setMemberActive(address member, bool active)
        external
        onlyOwner
    {
        require(bytes(memberNames[member]).length != 0, "Not registered");
        isActiveMember[member] = active;
    }

    // -------------------------
    // Interest configuration
    // -------------------------

    function setGlobalInterest(string calldata currency, string calldata percentStr)
        external
        onlyOwner
    {
        globalInterestFP[currency] = _stringPercentToFP(percentStr);
    }

    // -------------------------
    // Balance management
    // -------------------------

    function setInitialBalance(
        address member,
        string calldata currency,
        string calldata amountStr,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        uint256 amountFP = _stringToFP(amountStr);
        accounts[member][currency].balanceFP = amountFP;

        _log(
            member,
            currency,
            ActionType.INIT,
            amountFP,
            amountFP,
            globalInterestFP[currency],
            remarks
        );
    }

    function addFunds(
        address member,
        string calldata currency,
        string calldata amountStr,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        uint256 amountFP = _stringToFP(amountStr);
        Account storage acc = accounts[member][currency];
        acc.balanceFP += amountFP;

        _log(
            member,
            currency,
            ActionType.DEPOSIT,
            amountFP,
            acc.balanceFP,
            globalInterestFP[currency],
            remarks
        );
    }

    function subtractFunds(
        address member,
        string calldata currency,
        string calldata amountStr,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        uint256 amountFP = _stringToFP(amountStr);
        Account storage acc = accounts[member][currency];
        require(acc.balanceFP >= amountFP, "Insufficient balance");
        acc.balanceFP -= amountFP;

        _log(
            member,
            currency,
            ActionType.WITHDRAW,
            amountFP,
            acc.balanceFP,
            globalInterestFP[currency],
            remarks
        );
    }

    function adminOverrideBalance(
        address member,
        string calldata currency,
        string calldata newBalanceStr,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        uint256 newBalanceFP = _stringToFP(newBalanceStr);
        accounts[member][currency].balanceFP = newBalanceFP;

        _log(
            member,
            currency,
            ActionType.ADMIN_OVERRIDE,
            newBalanceFP,
            newBalanceFP,
            globalInterestFP[currency],
            remarks
        );
    }

    // -------------------------
    // Interest & payouts
    // -------------------------

    function manualInterestOrPayout(
        address member,
        string calldata currency,
        string calldata amountStr,
        bool isInterest,
        string calldata remarks
    ) internal onlyOwner onlyActive(member) {
        uint256 amountFP = _stringToFP(amountStr);
        Account storage acc = accounts[member][currency];

        if (isInterest) {
            acc.balanceFP += amountFP;
            _log(
                member,
                currency,
                ActionType.MANUAL_INTEREST,
                amountFP,
                acc.balanceFP,
                globalInterestFP[currency],
                remarks
            );
        } else {
            require(acc.balanceFP >= amountFP, "Insufficient balance");
            acc.balanceFP -= amountFP;
            _log(
                member,
                currency,
                ActionType.PAYOUT,
                amountFP,
                acc.balanceFP,
                globalInterestFP[currency],
                remarks
            );
        }
    }

    function batchApplyInterest(
        string calldata currency,
        string calldata remarks
    ) external onlyOwner {
        uint256 fp = globalInterestFP[currency];

        for (uint256 i = 0; i < allMembers.length; i++) {
            address member = allMembers[i];
            if (!isActiveMember[member]) continue;

            Account storage acc = accounts[member][currency];
            if (acc.balanceFP == 0 || fp == 0) continue;

            uint256 interestAmountFP = (acc.balanceFP * fp * 100) / 1e18;
            acc.balanceFP += interestAmountFP;

            _log(
                member,
                currency,
                ActionType.INTEREST_APPLIED,
                interestAmountFP,
                acc.balanceFP,
                fp,
                remarks
            );
        }
    }

    function batchPayout(
        string calldata currency,
        string calldata amountPerMemberStr,
        string calldata remarks
    ) external onlyOwner {
        for (uint256 i = 0; i < allMembers.length; i++) {
            address member = allMembers[i];
            if (!isActiveMember[member]) continue;

            manualInterestOrPayout(
                member,
                currency,
                amountPerMemberStr,
                false,
                remarks
            );
        }
    }

    // -------------------------
    // Views
    // -------------------------

    function getBalanceFP(address member, string calldata currency)
        external
        view
        returns (uint256)
    {
        return accounts[member][currency].balanceFP;
    }

    function getHistoryCount(address member) external view returns (uint256) {
        return historyCount[member];
    }

    function getHistoryEntry(address member, uint256 index)
        external
        view
        returns (HistoryEntry memory)
    {
        return history[member][index];
    }

    function getAllMembers() external view returns (address[] memory) {
        return allMembers;
    }
}
