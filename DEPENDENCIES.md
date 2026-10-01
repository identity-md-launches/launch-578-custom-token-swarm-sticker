# Vendored dependencies

These are ordinary source files, not Git submodules. Builds require no dependency
downloads. Unused OpenZeppelin modules and upstream repository tooling are omitted.

| Dependency | Release | Exact upstream commit | Delivered files |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/69c8def5f222ff96f2b5beff05dfba996368aa79) | v5.1.0 | `69c8def5f222ff96f2b5beff05dfba996368aa79` | ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093, MIT license |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/1eea5bae12ae557d589f9f0f0edae2faa47cb262) | v1.9.4 | `1eea5bae12ae557d589f9f0f0edae2faa47cb262` | `src/`, MIT and Apache-2.0 licenses; used only for testing |

Both snapshots were obtained from GitHub archives at the commits above. Vendored
files are unmodified. Their SHA-256 checksums, using paths relative to the project
root, are in each library's `SHA256SUMS` file:

```sh
sha256sum --check lib/openzeppelin-contracts/SHA256SUMS
sha256sum --check lib/forge-std/SHA256SUMS
```

The application does not need any linked or externally deployed library. Foundry
and the pinned Solidity compiler are build tools supplied by the execution
environment; compiler binaries are not part of this repository.
