# wrapped ThUSD (wThUSD)

A token wrapper for ThUsd

## What is this and why 

We’re introducing a new icon and a dApp called Wrapped ThUsd (wThUSD).

- A user wraps ThUsd via the dApp and receives wThUsd 1:1.
- wThUSD can be used in bonds and high‑yield, non–Sharia‑compliant vaults.
- ThUsd and sThUsd remain invested/backed only by Sharia‑compliant strategies.
- Coming soon: wSthUsd, a non–Sharia‑compliant vault.

## Requirements

- The wrapping is implemented using an ERC4626 standard vault
- The rate between ThUsd and wThUsd is always 1:1
- There is no expected appreciation of the vault shares, so any tokens deposited in the vault should be rescueable by owners

## Implementation details

A generic wrapper called `TharwaWrapper` which is ERC4626 compliant, accepting an underlying asset deposits, and gives shares at 1:1 ratio always.
The wThUsd inherits this `TharwaWrapper`, but we can spin other wrappers if needed. 

### TharwaWrapper implementation

- A token that inherits Openzeppelin's ERC4626
- The functions `deposit()` and `mint()` re-direct to an internal `_wrap()` function
- The functions `withdraw()` and `redeem()` re-direct ot an internal `_unwrap()` function
- `_wrap()` pulls ThUsd from the caller, and gives `wThUsd` to the receiver (at 1:1 rate)
- `_unwrap()` does the opposite way
- a `rescueErc20Token()` function allows withdrawing any ERC20 in the vault balance, except for thUsd, which only allows to withdraw the difference between the balance and the total supply of the vault. 


