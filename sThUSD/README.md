### Staked Tharwa USD

# sThUSD — Tharwa Staked USD (ERC‑4626 Vault)

sThUSD is an ERC‑4626 vault that lets users stake thUSD and earn protocol yield that vests linearly over time. It includes donation‑attack–resistant accounting, optional entry/exit fees, cooldowns, and admin‑managed yield top‑ups.

- Contract: [src/sThUSD.sol](./src/sThUSD.sol)
- Silo: [src/ThUSDSilo.sol](./src/ThUSDSilo.sol)
- Tests: [test/sThUSD.t.sol](./test/sThUSD.t.sol)
- Script: `script/sThUSD.s.sol`

## Key Concepts

- [Underlying asset] thUSD (18 decimals). Examples use explicit 1e18 units (e.g., `100_000e18`).
- [Shares] Depositors receive sThUSD shares. Share price = `totalAssets() / totalSupply()`.
- [Yield vesting] Admin `addYield(amount)`; amount vests linearly over `vestingPeriod` (default 30 days). While vesting, unvested yield is excluded from `totalAssets()`, preventing new depositors from capturing queued yield.
- [Cooldown + Silo] When `cooldownPeriod > 0` (ON), users exit via staged cooldown:
  - Start via `cooldownAssets(assets)` or `cooldownShares(shares)`.
  - Underlying thUSD moves from the vault to `ThUSDSilo` and is queued for the user.
  - After `cooldownPeriod`, user calls `unstake(receiver)` to claim the queued thUSD.
  - Multiple cooldown calls aggregate queued amount and reset the timer to the latest call.
  - When `cooldownPeriod == 0` (OFF), standard ERC4626 `withdraw`/`redeem` are enabled and no cooldown/unstake is required.
- [Fees] Optional entry and exit fees (each capped at 10%) sent to `feeRecipient`.
- [Donation‑safe accounting] `_pooledAssets` tracks accounted assets; `totalAssets()` excludes unvested yield to prevent donation/inflation attacks.

## Roles

Defined in [src/sThUSD.sol](./src/sThUSD.sol):
- DEFAULT_ADMIN_ROLE — governance/admin (sets vesting/cooldown, controls).
- PAUSER_ROLE — can `pause()` / `unpause()`.
- YIELD_MANAGER_ROLE — can `addYield()` (requires supply > 0 and no active vest).
- FEE_MANAGER_ROLE — can `setFees(entryFeeBps, exitFeeBps, feeRecipient)`.

## Parameters (defaults)

- vestingPeriod: `30 days` (set via `setVestingPeriod(newPeriod)`).
- cooldownPeriod: `0, 3 days, or 7 days` (set via `setCooldownPeriod(newPeriod)`).
- fees: 0 bps by default. Each of entry/exit fees can be up to 1000 bps (= 10%).

## Core Flows

- Deposit `deposit(assets, receiver)`
  - Mints shares to `receiver` (net of entry fee if set) at current share price.

- Mint `mint(shares, receiver)`
  - Alternative to deposit; computes required assets and applies entry fee on assets.

- Withdraw/Redeem `withdraw(assets, receiver, owner)` / `redeem(shares, receiver, owner)`
  - Available only when `cooldownPeriod == 0` (cooldown OFF).
  - Burns shares and transfers assets (minus exit fee if set).

- Cooldown (ON) `cooldownAssets(assets)` / `cooldownShares(shares)`
  - Available only when `cooldownPeriod > 0` (cooldown ON).
  - Moves underlying thUSD from the vault into the `ThUSDSilo` and queues it for the caller.
  - Exit fee (if set) is charged at cooldown time. Preview via `previewWithdraw(assets)`/`previewRedeem(shares)`.

- Claim (ON) `unstake(receiver)`
  - After the user’s `cooldownEnd`, transfers all queued thUSD from the silo to `receiver`.
  - Multiple cooldowns aggregate amounts; the claim happens once, after the latest `cooldownEnd`.

- Add Yield `addYield(amount)` (YIELD_MANAGER_ROLE)
  - Transfers thUSD into the vault and starts linear vesting over `vestingPeriod`.
  - Requires `totalSupply() > 0` and no active vest (`_unvestedAmount() == 0`).

See [src/sThUSD.sol](./src/sThUSD.sol): `totalAssets()`/`_unvestedAmount()` (vesting/donation‑safe), `_deposit()`/`_withdraw()` (fees, cooldown), `addYield()`.

## Accounting Model

- `totalAssets()` returns `_pooledAssets - unvestedAmount`.
- Deposit: `_pooledAssets += (assets - entryFee)`.
- Exit (cooldown OFF): on `withdraw/redeem`, `_pooledAssets -= (assets + exitFee)`.
- Exit (cooldown ON): on `cooldown*`, `_pooledAssets -= (assets + exitFee)` and thUSD moves to the silo; `unstake` later transfers from the silo to the user (no impact on `_pooledAssets`).
- Add yield: `_pooledAssets += amount` immediately, but `totalAssets()` excludes the unvested portion until recognized linearly.


## Fees (optional)

- Entry fee (bps on total sent): shares minted on net assets; fee sent to `feeRecipient`.
- Exit fee (bps on assets out):
  - cooldown OFF: charged on `withdraw/redeem`.
  - cooldown ON: charged at `cooldownAssets/cooldownShares` time (when moving to the silo).
- Configure via `setFees(entryFeeBps, exitFeeBps, feeRecipient)`.

## Controls & Safety

- Pause via `pause()` / `unpause()` (PAUSER_ROLE).
- Blacklist via `setBlacklisted(addr, bool)`; transfers/withdraws rejected for blacklisted addresses.
- Rescue tokens via `rescueERC20(token, to, amount)`; never pulls from accounted thUSD.

## Development

- Build, test, and coverage

```sh
forge build
forge test
forge coverage
```

