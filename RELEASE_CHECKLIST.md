# Release checklist

Nothing is pushed to the public repository until every box is ticked for the exact
commit being pushed. A pack is released only once a director of Synthro (Pty) Ltd has
signed it off — the signed record is kept with the company's records, not here.

## Content

- [ ] **No customer data**, customer names or anything that identifies a customer or
      their people.
- [ ] **No credentials** of any kind: keys, tokens, passwords, connection strings,
      private keys, signing secrets.
- [ ] **No internal addresses**: hosts, project references, bucket names, internal URLs,
      email addresses.
- [ ] **No weakness of Synthro's own systems**, and nothing describing how to exploit one.
      Methods and patterns only.
- [ ] **No incident specifics**: no dates, systems, people or values from any real
      incident. Describe the *kind* of mistake, never the event.
- [ ] **No commercial information**: prices, costs, margins, contract terms.
- [ ] **No product material**: no product code, prompts, knowledge base, document
      templates, or Synthro's own data model. Examples use the neutral sample schema.
- [ ] **Nothing still open.** A known, unfixed fault is never published.
- [ ] **Only our own work**, or MIT-compatible work with its notice kept. Nothing
      copyleft.

## Checks

- [ ] `node scripts/scrub-check.mjs --self-test` passes.
- [ ] `node scripts/scrub-check.mjs --release` passes, with the local denylist present
      and up to date.
- [ ] Every pack's proof passes, e.g. `bash packs/migration-rounds/proof/run.sh`.
- [ ] A person read every changed file in full. Tools are a second line, not the first.

## History

- [ ] The repository's history began fresh. Nothing was copied in with its git history
      from a private repository.
- [ ] The pushed commit is the one that was checked and signed off.
