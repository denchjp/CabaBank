/**
 * FamilyBank (Owner-only)
 * - Multi-currency balances using string currency codes ("PHP", "USD")
 * - Interest input as whole percent (5 = 5%)
 * - Global interest per currency
 * - Batch interest for all active members (no applyInterest function)
 * - Manual interest & manual payout
 * - Batch payout
 * - Editable member names
 * - Active/inactive member flag
 * - Per-member history + CSV-friendly events
 * - Owner-only interaction
 * - All transactions require member to be active
 */

contract FamilyBank {
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

    // Global interest per currency (basis points)
    mapping(string => uint256) public globalInterestBP;

    struct Account {
        uint256 balance;
    }

    // member => currency => account
    mapping(address => mapping(string => Account)) public accounts;

    // History
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
        uint256 amount;
        uint256 balanceAfter;
        uint256 timestamp;
        string remarks;
    }

    mapping(address => mapping(uint256 => HistoryEntry)) public history;
    mapping(address => uint256) public historyCount;

    // CSV-friendly event
    event LedgerEvent(
        address indexed member,
        string currency,
        ActionType action,
        uint256 amount,
        uint256 balanceAfter,
        uint256 interestBP,
        uint256 timestamp,
        string remarks
    );

    // Internal logging
    function _log(
        address member,
        string memory currency,
        ActionType action,
        uint256 amount,
        uint256 balanceAfter,
        uint256 interestBP,
        string memory remarks
    ) internal {
        uint256 idx = historyCount[member];
        history[member][idx] = HistoryEntry({
            currency: currency,
            action: action,
            amount: amount,
            balanceAfter: balanceAfter,
            timestamp: block.timestamp,
            remarks: remarks
        });
        historyCount[member]++;

        emit LedgerEvent(
            member,
            currency,
            action,
            amount,
            balanceAfter,
            interestBP,
            block.timestamp,
            remarks
        );
    }

    // Convert percent to basis points
    function _percentToBP(uint256 percent) internal pure returns (uint256) {
        return percent * 100; // 5 → 500 bp
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

    function setGlobalInterest(string calldata currency, uint256 percent)
        external
        onlyOwner
    {
        globalInterestBP[currency] = _percentToBP(percent);
    }

    // -------------------------
    // Balance management
    // -------------------------

    function setInitialBalance(
        address member,
        string calldata currency,
        uint256 amount,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        accounts[member][currency].balance = amount;

        _log(
            member,
            currency,
            ActionType.INIT,
            amount,
            amount,
            globalInterestBP[currency],
            remarks
        );
    }

    function addFunds(
        address member,
        string calldata currency,
        uint256 amount,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        Account storage acc = accounts[member][currency];
        acc.balance += amount;

        _log(
            member,
            currency,
            ActionType.DEPOSIT,
            amount,
            acc.balance,
            globalInterestBP[currency],
            remarks
        );
    }

    function subtractFunds(
        address member,
        string calldata currency,
        uint256 amount,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        Account storage acc = accounts[member][currency];
        require(acc.balance >= amount, "Insufficient balance");
        acc.balance -= amount;

        _log(
            member,
            currency,
            ActionType.WITHDRAW,
            amount,
            acc.balance,
            globalInterestBP[currency],
            remarks
        );
    }

    function adminOverrideBalance(
        address member,
        string calldata currency,
        uint256 newBalance,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        accounts[member][currency].balance = newBalance;

        _log(
            member,
            currency,
            ActionType.ADMIN_OVERRIDE,
            newBalance,
            newBalance,
            globalInterestBP[currency],
            remarks
        );
    }

    // -------------------------
    // Interest & payouts
    // -------------------------

    function batchApplyInterest(
        string calldata currency,
        string calldata remarks
    ) external onlyOwner {
        uint256 bp = globalInterestBP[currency];

        for (uint256 i = 0; i < allMembers.length; i++) {
            address member = allMembers[i];

            if (!isActiveMember[member]) continue;

            Account storage acc = accounts[member][currency];
            if (acc.balance == 0 || bp == 0) continue;

            uint256 interestAmount = (acc.balance * bp) / 10000;
            acc.balance += interestAmount;

            _log(
                member,
                currency,
                ActionType.INTEREST_APPLIED,
                interestAmount,
                acc.balance,
                bp,
                remarks
            );
        }
    }

    function manualInterestOrPayout(
        address member,
        string calldata currency,
        uint256 amount,
        bool isInterest,
        string calldata remarks
    ) external onlyOwner onlyActive(member) {
        Account storage acc = accounts[member][currency];

        if (isInterest) {
            acc.balance += amount;
            _log(
                member,
                currency,
                ActionType.MANUAL_INTEREST,
                amount,
                acc.balance,
                globalInterestBP[currency],
                remarks
            );
        } else {
            require(acc.balance >= amount, "Insufficient balance");
            acc.balance -= amount;
            _log(
                member,
                currency,
                ActionType.PAYOUT,
                amount,
                acc.balance,
                globalInterestBP[currency],
                remarks
            );
        }
    }

    function batchPayout(
        string calldata currency,
        uint256 amountPerMember,
        string calldata remarks
    ) external onlyOwner {
        for (uint256 i = 0; i < allMembers.length; i++) {
            address member = allMembers[i];

            if (!isActiveMember[member]) continue;

            manualInterestOrPayout(
                member,
                currency,
                amountPerMember,
                false,
                remarks
            );
        }
    }

    // -------------------------
    // Views
    // -------------------------

    function getBalance(address member, string calldata currency)
        external
        view
        returns (uint256)
    {
        return accounts[member][currency].balance;
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
