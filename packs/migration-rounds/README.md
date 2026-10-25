# Migration Rounds

A twelve-round verification method for PostgreSQL and Supabase migrations, and a
harness that proves it works.

Most migration checks prove a file *applied*. These rounds prove it *behaves*: that a
signed-in user sees exactly what they should, that two requests at the same moment
cannot both win, that a function you created can actually run, and that the policy you
wrote is not quietly evaluated once per row.

## What is in here

| File | What it is |
|---|---|
| [SKILL.md](SKILL.md) | The procedure, as a Claude Code skill. Also reads fine as a plain checklist |
| [ROUNDS.md](ROUNDS.md) | Every round in full, with the queries to run |
| [proof/](proof/) | Six real defect classes, each with a broken migration, a fixed one and a test, run on a throwaway Postgres |

## Use it with Claude Code

Copy the folder into your project or your user skills:

```bash
cp -r packs/migration-rounds .claude/skills/migration-rounds        # this project
cp -r packs/migration-rounds ~/.claude/skills/migration-rounds      # every project
```

Claude loads it when you write or review a migration, a policy, a database function or
a GRANT. Without Claude, read SKILL.md and work through it by hand — nothing in it
depends on an assistant.

## See the proof

```bash
bash packs/migration-rounds/proof/run.sh
```

Needs Docker. The container runs with no network and is deleted when the script exits.

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

What each case shows is in [proof/README.md](proof/README.md).

**The harness is tested against itself.** With one fix replaced by its broken version
and one matrix switched to run as the table owner, it reports `PROOF FAILED: 2/6` and
exits 1. A test that cannot fail proves nothing.
