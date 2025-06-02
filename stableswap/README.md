### Tharwa Stableswap

- Tharwa Stableswap is a stableswap pool for thUSD
- It is a simple stableswap pool that allows users to swap between DAI, USDC, USDT and thUSD
- it transfers the stablecoins to the treasury for RWA investments and thUSD to the user


to install dependencies run :

```bash
forge install foundry-rs/forge-std --no-git
forge install openzeppelin/openzeppelin-contracts --no-git
```

to deploy Tharwa Stableswap run :

```bash
forge script script/thUSDSwap.s.sol:thUSDSwapScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```
to run tests run :

```bash
forge test
```

 