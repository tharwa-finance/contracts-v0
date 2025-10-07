# Tharwa - Points claim system

## Implementations

### Merkle based distribution system

Merkle-tree based distribution system. 

See [merkleDistributor.docs.md](./doc/merkleDistributor.docs.md).

- Good for setting a large amount of receivers of the distribution. 
- Operational costs: updating the merkle root if claims need to be updated constantly.

### Linear vesting distribution system

See [vestedDistributor.docs.md](./doc/vestedDistributor.docs.md). 

- Good for setting smaller amounts of receivers
- Linear vesting allows claimable amounts updating on every block. 
