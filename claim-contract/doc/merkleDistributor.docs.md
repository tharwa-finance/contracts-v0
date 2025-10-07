# Tharwa - Merkle based Points claim system

## Requirements

- Users should be able to claim their points and receive their tokens
- The contract should support claims from multiple tokens, although it is only intended to be used with one token initially
- Users can claim their tokens regularly
- Keep operational costs of the Distributor contract low
- Accounts should be able to claim on behalf of other accounts (to avoid implementing claim functions in contracts earning points)
- Accounts should be able to pass a receiver who will receive the claimed tokens
- Each season accounting should start from 0
- It should be possible to claim multiple sessions in one transaction

## Technical specs

Contracts:

- `TharwaDistributor.sol`

### Mechanics overview

- Merkle-tree + based contract
- Pull based contract (no airdrops, users have to claim)
- The contract is organized into "campaigns" which can be a "season" or other future custom campaigns if needed
- For the correct functioning, the contract needs to have all the claimable funds in its balance

For each campaign, the following applies:

- Each campaign has an individual merkle root
- Each campaign has individual claimable amounts for each (account,token) pair
- Each campaign claimable amount starts from 0, and it is isolated from other campaigns.

- Claimable amounts are calculated off-chain together with merkle root and merkle proofs for each set of (campaign,account,token). This amount can never decrease, so the off-chain component needs to have safeguards to ensure it
- A campaign merkle root can be updated at any time, as it should point to incremental-only claimable amounts
- The contract keeps track of the historical accumulated **claimed** amounts for each (campaign,account,token)
- On every claim, the merkle proofs are validated agains the corresponding campaign merkle root.
- On every claim, the caller passes the off-chain total **claimable** amount, the contract reads the onchain-registered **claimed** amount, and the receiver only transfers the difference between them.
  - This is a very robust protection against double claiming
  - _Note_: if the off-chain calculator gives a lower amount than what has been already claimed, it should revert with an error that we monitor and immediately fix.

### Main state variables

#### `merkleRoot` mapping:

- Used to validate the merkle proofs. Each campaign has a merkle root.
- The merkle roots are calculated offchain and set in the contract only by an allowed account
- The merkle roots can be updated at any time.
- `mapping(uint256 campaign => bytes32 root) merkleRoots`;
- Leaves of the merkle tree are (`address account`, `address token`, `uint256 amount`)

#### `totalClaimed` mapping:

- Keeps track of the total claimed tokens for each (campaign, account, token) set.
- `mapping(uint256 campaign => mapping(address account => mapping(address token => uint256 totalClaimed))) totalClaimed`;

### Admin state-changing functions

#### `updateMerkleRoot(uint256 campaign, bytes32 newRoot) onlyAdmin`:

- Allows an admin account to update the merkle-root of a campaign, to update the claimable amounts.
- It can be called as frequently as wanted
- The updated root should yield increasing-only rewards for every account. A root can never configure a lower claim value for any account.

### External state-changing functions

#### `claimOnBehalf()`:

**Description:**

- Allows `msg.sender` to claim on behalf of `account`
- The claimed `amount` is added to the `totalClaimed` of `account`, which is also the receiver of the tokens.
- `msg.sender` is only a facilitator, and it is not involved at all in the funds flow

**Inputs:**

- `uint256 campaign`: equivalent to "season". It allows pointing to the right merkle root.
- `address account`: account to claim on behalf of.
- `address token`: token to claim.
- `uint256 totalClaimableSinceStart`: the total claimable amount up until now.including what has been already claimed previously (think of a better naming).
- `bytes32[] calldata proof`: merkle proof that links the merkleroot with the leaves `(account, token, amount)`.

#### `claim()`

**Description:**

- Allows `msg.sender` to claim and transfer claimed tokens to `receiver`
- The claimed `amount` is added to the `totalClaimed` of `msg.sender`, but tokens will be sent to `receiver`

**Inputs:**

- `uint256 campaign`: equivalent to "season". It allows pointing to the right merkle root.
- `address token`: token to claim
- `uint256 totalClaimableSinceStart`: the total claimable amount up until now.including what has been already claimed previously (think of a better naming).
- `receiver`: who receives the tokens. Not involved in the proof validation at all.
- `bytes32[] calldata proof`: merkle proof that links the merkleroot with the leaves `(msg.sender, token, amount)`.

#### `multicall()`

- This to allow calling multiple functions in the same transaction using delegatecall. Although we could also leverage EIP7702

# Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

- `forge build` should instal all dependencies and build the project
- `forge test`
- `forge coverage`
