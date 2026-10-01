The STICK suite tests the deployed `SwarmSticker` contract through its public
interface. It uses the existing vendored Foundry and OpenZeppelin dependencies;
no network, fork, environment mutation, or additional package is required.

- `SwarmSticker.t.sol` retains the deployment, metadata, fixed supply, events,
  exact launch allocations, transfer failures, and absence of administrative
  entrypoint checks. Fuzz inputs are bounded without discarded cases.
- `SwarmSticker.adversarial.t.sol` adds explicit integer boundaries and allowance
  lifecycle tests: replay after exhaustion, revocation of unlimited approval,
  replacement, owner/spender isolation, non-transitive authority, and retry after
  insufficient funds. Fuzz properties check cumulative spending limits, repeated
  fee-free round trips, and that failed spending preserves usable approval.
- `SwarmSticker.invariant.t.sol` extends the existing four-actor model. Nine
  selected handler actions mix successful transfers and approvals with expected
  failures, revocation, and full-balance round trips. Balances and all sixteen
  actor-to-actor allowances must match independently maintained expectations;
  their sum must remain exactly one billion tokens with 18 decimals. Metadata
  must remain unchanged. After every sequence, all actors must be able to move
  their full balances to one recipient.

Expected failures are caught inside the handler and checked for the exact error.
The handler leaves the balance model unchanged on failure and retains approvals
made before the failed call. Invariants then check rollback of all tracked
balances and allowances. Unexpected reverts and failed handler assertions fail
the campaign. A deterministic handler sequence also exercises the boundary
actions, including both direct and delegated failure paths.

Run `forge build` and `forge test`. Inline settings request 1,000 cases per fuzz
property and 256 invariant sequences of depth 96 per invariant. For checks with
all generated build artifacts confined to the disposable test area, use:

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
forge test --out test/scratch/out --cache-path test/scratch/cache
```

The supplied protected launch harness was read as an integration specification.
It depends on the external launch factory/liquidity code, Uniswap v4, and resolved
launch parameters that are absent here. The local allocation test verifies token
movements only; it does not claim to verify pool initialization, swaps, or the
10 ETH opening market cap. Those remain checks for the protected launch verifier.
