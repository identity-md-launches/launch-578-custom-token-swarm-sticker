# Swarm Sticker (STICK)

A plain ERC-20 community token for the IMD swarm sticker pack. The complete
production contract is `src/SwarmSticker.sol`, using the vendored OpenZeppelin
ERC-20 implementation without transfer overrides.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Contract identifier | `src/SwarmSticker.sol:SwarmSticker` |
| Name | `Swarm Sticker` |
| Symbol | `STICK` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000 STICK` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate constructor caller, `msg.sender` |
| Application contracts | None |
| Compiler | Solidity `0.8.26`, optimizer enabled, 200 runs |
| EVM target | Cancun |
| Bytecode metadata | `bytecode_hash = "none"`, CBOR metadata disabled |

The constructor mints the whole supply once and emits the standard mint
`Transfer` event. A direct deployment credits the deployer; an IMD
`ProjectFactory.launchCustom` deployment credits the factory, including when
deployed with CREATE2. The token makes no constructor transfers to other parties
and has no initialization step or dependency on chain addresses.

There are no fees, rebases, public mint or burn methods, owner, roles, pause,
blacklist, seizure, rescue, or upgrade functions. The total supply remains fixed.
All holders, including the factory, distributor, and PoolManager, follow identical
transfer rules. Transfers do not make external calls or invoke recipient hooks.

## Launch economics and assumptions

Pool allocation and opening market cap are external launch settings, not rules
enforced by the token. Preserve these inputs in the separately prepared launch
manifest:

| Setting | Value |
| --- | --- |
| `kind` | `custom_token` |
| `economics.poolBps` | `8800` (88% of the whole supply) |
| `economics.initialMarketCapWei` | `10000000000000000000` (10 ETH) |
| `economics.remainderTo` | The requester's wallet supplied by the launch page |
| `pool.pairedCurrency` | Native ETH, represented by the zero address |

The supplied IMD launch definition reserves 10% of the whole supply for the
swarm before the pool and remainder allocations: 2% for accepted contributors
and 8% for connected paired seats, distributed by the launch's MerkleDistributor.
Accordingly, the nominal allocation is:

| Destination | Share | STICK |
| --- | --- | --- |
| Swarm distributor | 10% | 100,000,000 |
| Pool | 88% | 880,000,000 |
| Requester's wallet | 2% | 20,000,000 |

The factory handles distribution after construction. Liquidity rounding may use
slightly less than the nominal pool budget; the launch system must account for
and forward any residual according to its policy. The 10 ETH starting market cap
implies a nominal starting price of `0.00000001 ETH` per STICK; it is a price
setting, not an instruction to deposit 10 ETH or a guarantee of market value.

No requester wallet, chain ID, factory address, PoolManager address, pool fee,
tick spacing, or liquidity range was supplied. The launch operator must resolve
and validate those parameters, derive the pool's price and liquidity using the
launch system, and confirm the remainder wallet before release. No placeholder
wallet or production manifest is included. No special token exemptions or
constructor addresses are needed.

## Build and test

Install Foundry and make Solidity 0.8.26 available in its normal compiler cache.
All Solidity dependencies needed for this project are ordinary files under
`lib/`; no `forge install`, submodules, network fork, or package manager is needed.
Once the pinned compiler is cached, builds and tests work without network access.

```sh
forge build
forge test
forge fmt --check
```

Tests do not read or set environment variables or depend on test order. FFI and
filesystem cheatcode access are disabled. The suite covers metadata and supply,
constructor events, deployment by a caller and CREATE2 factory, exact transfers,
zero and self transfers, finite and infinite allowances, revocation, transfer
events, insufficient balances/allowances, invalid addresses, rollback on failed
transfers, absent admin functions, and forbidden runtime opcodes. Fuzz tests run
512 cases each; stateful invariants run 128 sequences of up to 64 operations and
compare balances and allowances against an independent model.

The local launch-flow test checks exact distributor, claimant, pool, and wallet
transfers, including both directions of pool transfers. It does not initialize
or swap against a real Uniswap v4 PoolManager. The supplied protected integration
harness requires the network's factory/liquidity infrastructure and resolved
manifest; its actual pool initialization, liquidity seeding, and swap checks
remain the independent launch verifier's responsibility.

## Operational responsibilities

The launch operator must deploy the exact reviewed artifact through the intended
factory, confirm metadata, supply and the factory's initial balance, validate the
distribution and pool parameters, and verify the deployed source on the chosen
chain. The target chain must support the configured Cancun EVM target. The
separate manifest stage records the artifact and exact supply above. This project
does not read keys, broadcast transactions, create a pool, or deploy a distributor.

There is no token administrator and no post-launch maintenance or privileged
recovery mechanism. Holders control their transfers and approvals. Approvals
replace the previous value; clients should account for the standard ERC-20
allowance-change race (e.g. revoke and confirm before increasing a nonzero
allowance). `type(uint256).max` is supported as an unlimited approval and remains
unchanged when spent. Ordinary finite allowances decrease on `transferFrom`;
OpenZeppelin 5.1 does not emit an `Approval` event for that decrease. Zero-value
transfers to valid addresses are allowed and emit `Transfer`; transfers to the
zero address and approvals to a zero spender revert. Failed operations revert
atomically with OpenZeppelin's ERC-6093 errors.

The contract rejects ordinary ETH sends. Forced ETH or tokens sent to the token
contract cannot be recovered. Holding STICK grants no on-chain redemption,
governance, or sticker-delivery entitlement in this implementation.

Passing tests is not a security audit. Obtain the network's independent
adversarial review before release. Local validation uses Foundry unit, fuzz and
invariant tests; Slither and Mythril were not run. Dependency provenance and
licenses are recorded in `DEPENDENCIES.md`.
