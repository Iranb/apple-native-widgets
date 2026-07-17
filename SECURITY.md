# Security and privacy

The widget extensions are display-only. They must never read credentials or mutate HPC jobs.

- Keep tokens, cookies, passwords, private keys, account stores, and raw portal responses outside this repository.
- Feed widgets only redacted JSON snapshots copied into their sandboxed Application Support directories.
- The default preview command uses synthetic data. `./render-previews.sh --live` writes to the ignored `previews-live/` directory so real aliases and project names are not committed accidentally.
- Before opening an issue, remove usernames, account aliases, local paths, job identifiers, trace mappings, and unpublished research details from logs and screenshots.

Please report security issues privately to the repository owner instead of opening a public issue.
