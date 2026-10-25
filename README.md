# Synthro Guardrails

Engineering guardrails from building a multi-tenant SaaS on PostgreSQL and Supabase —
written down as checklists, packaged as Claude Code skills, and **proven by tests that
have to catch the broken version before they pass the fixed one.**

Every rule here exists because breaking it is easy, looks correct in review, and passes
the usual checks. The proofs show the mistake happening and the fix stopping it.

## Packs

| Pack | What it guards | Status |
|---|---|---|
| [**Migration Rounds**](packs/migration-rounds/) | Database migrations, row-level security, SECURITY DEFINER functions, grants, races and slow policies | ✅ Released, with a [proof harness](packs/migration-rounds/proof/) |

More packs are planned.

## Try it in two minutes

```bash
git clone <this repository>
cd synthro-guardrails
bash packs/migration-rounds/proof/run.sh      # needs Docker
```

The harness runs six real defect classes on a throwaway, network-isolated Postgres.
Each one is a migration that applies cleanly, passes review, and is wrong:

```
case                         broken → fixed (as user)
01-definer-cross-tenant      DEFECT 1/3 → CLEAN 3/3
02-policy-recursion          DEFECT 0/2 → CLEAN 2/2       owner-blind
03-policy-helper-grant       DEFECT 0/2 → CLEAN 2/2       owner-blind
04-single-use-token-race     DEFECT 0/2 → CLEAN 2/2
05-function-never-called     DEFECT 0/2 → CLEAN 2/2
06-rls-per-row-auth          DEFECT 1/2 → CLEAN 2/2
PROOF PASSED: 6/6 cases — every defect detected, every fix clean.
```

`owner-blind` means the same test, run as the table owner, gives the same answer for the
broken and the fixed database. That is why every test here runs as a signed-in user.

## Use a pack with Claude Code

```bash
cp -r packs/migration-rounds ~/.claude/skills/migration-rounds
```

Or read the pack's `SKILL.md` and work through it by hand. Nothing in it depends on an
assistant.

## Principles

- **Applied is not working.** A migration that applies has proven its syntax. Behaviour is
  proven separately, as a real user.
- **A test that cannot fail proves nothing.** Every proof case must catch its broken
  version. The harness is itself tested by sabotaging a fix and checking it fails.
- **A missing signal is not a good signal.** A check that sees nothing reports "nothing
  checked", never "pass".
- **Measure, never recall.** Clocks, column names, constraint values and applied versions
  are read from the system, not remembered.

## License

[MIT](LICENSE). Copyright Synthro (Pty) Ltd. Created by Naphtali Tsikada.
See [NOTICE.md](NOTICE.md) for the trade mark notice, and
[CONTRIBUTING.md](CONTRIBUTING.md) to add a case.
