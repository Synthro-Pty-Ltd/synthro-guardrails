# Contributing

Contributions are welcome — new proof cases most of all.

## The rules

1. **Sign off every commit** (`git commit -s`). Your sign-off certifies the
   [Developer Certificate of Origin 1.1](https://developercertificate.org): that you
   wrote the contribution, or otherwise have the right to submit it under this
   project's license.
2. **Your contribution is licensed under the MIT License**, the same as everything else
   here. There is no separate contributor agreement.
3. **Only your own work, or MIT-compatible work with its notice kept.** Nothing under a
   copyleft license.
4. **No real data.** No credentials, customer data, company names, personal details or
   real identifiers. Use the neutral sample schema (`workspaces`, `members`, `notes`)
   and synthetic ids that start `00000000-`.
5. **Prove it both ways.** A new proof case needs a broken version the matrix catches
   and a fixed version it passes. Run:

   ```bash
   node scripts/scrub-check.mjs
   bash packs/migration-rounds/proof/run.sh
   ```

## Reporting a security problem

If you find something in this repository that could cause harm if published — a
credential, personal data, anything that should not be public — do not open a public
issue. Report it privately through this repository's **Security** tab ("Report a
vulnerability").
