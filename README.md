# CabaBank
CabaBank is a private, owner‑controlled smart contract built for the Binance Smart Chain (BSC).
It acts as a secure, multi‑currency internal ledger for managing balances, interest, payouts, and transaction history for family members or trusted participants.

Designed for simplicity, transparency, and long‑term record‑keeping, FamilyBank provides a complete on‑chain accounting system with CSV‑friendly logs and strict access control.

🔒 Key Features
✔ Owner‑Only Access
All functions can only be executed by the contract owner.
Members cannot modify their own balances — ensuring full administrative control.

✔ Multi‑Currency Internal Ledger
Supports any currency using simple string identifiers:

Code
```
"PHP", "USD", "JPY", "EUR", etc.
```
Each member can hold balances in multiple currencies.

✔ Active Member Enforcement
All financial actions require the member to be active:

Deposits

Withdrawals

Interest

Payouts

Balance overrides

Inactive members are fully locked from transactions.

✔ Global Interest Rates (Percent-Based)
Interest is set per currency using whole percentages:

Code
```
5 → 5% → 500 basis points
```
No custom interest per member — simplified and consistent.

✔ Batch Interest for All Active Members
Interest is applied automatically to every active member holding a balance in the specified currency.

✔ Manual Interest & Manual Payout
Flexible adjustments for special cases:

Bonuses

Emergency withdrawals

Custom rewards

✔ Batch Payouts
Send a fixed payout amount to all active members in a currency.

✔ Editable Member Names
Update member names anytime for clarity and record accuracy.

✔ Full Transaction History
Every action is logged:

Initial balance

Deposits

Withdrawals

Interest

Manual interest

Payouts

Admin overrides

History is stored on-chain and accessible per member.

✔ CSV-Friendly Event Logs
Events are structured for easy export from BscScan:

Code
```
member, currency, action, amount, balanceAfter, interestBP, timestamp, remarks
```
Perfect for spreadsheets, accounting tools, or long-term archiving.

🧩 Use Cases
Family savings and lending system

Multi-currency allowance tracking

Private internal bank for small groups

Transparent shared fund management

Long-term financial history archiving

🛠 Tech Stack
Solidity 0.8.x

Binance Smart Chain (BSC)

EVM-compatible architecture

CSV-friendly event logging

Owner-only access control

📦 Contract Highlights
No external token transfers

No ERC20 dependencies

Pure internal ledger

Gas-efficient batch operations

Clean, readable architecture

📘 Example Operations
solidity
```
registerMember(0x123..., "Mama", true);
setInitialBalance(0x123..., "PHP", 50000, "Initial deposit");
addFunds(0x123..., "PHP", 2000, "Weekly allowance");
subtractFunds(0x123..., "PHP", 1500, "Groceries");
setGlobalInterest("PHP", 5);
batchApplyInterest("PHP", "Monthly interest");
manualInterestOrPayout(0x123..., "PHP", 1000, true, "Bonus");
batchPayout("PHP", 500, "Christmas gift");
```

📄 License
MIT License — free for personal and educational use.
