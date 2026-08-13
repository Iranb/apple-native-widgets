# Version and Branch Policy

The public repository keeps the Apple-native glass UI on `main`. Functional fixes remain isolated until they are reviewed and deliberately merged.

## Branch map

| Branch | Scope | HPC version | Status |
| --- | --- | --- | --- |
| `main` | Privacy-safe Apple-native glass UI | 3.1 (13) | Stable |
| `release/hpc-v3.1-glass` | Immutable rollback point for the glass UI | 3.1 (13) | Frozen |
| `agent/fix-hpc-gpu-availability` | Free/total GPU and CPU compatibility | 3.2 (15) | Isolated fix |
| `agent/fix-hpc-account-refresh` | Per-account visible refresh request | 3.1 (14) | Isolated fix |
| `agent/fix-deadline-header` | AI Deadline header correction | Independent | Isolated fix |

## Release rules

1. Keep `main` privacy-safe: use `com.example` identifiers, synthetic account aliases, and synthetic committed previews.
2. Never copy an installed app bundle, live snapshot, token, cookie, local path, or private preview into this repository.
3. Bump the HPC host and extension versions together. A branch-specific build number must not be reused for another HPC branch.
4. Preserve both widget kinds, `BJTUHPCNativeWidget` and `BJTUHPCWidget`, so existing desktop placements survive upgrades.
5. Run `scripts/verify-hpc-release.sh`, `./render-previews.sh`, and `./build.sh` before publishing a branch.
6. Merge isolated branches only after their draft PR is reviewed. Create the next combined release version after the selected fixes land on `main`.
