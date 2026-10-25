---
name: migration-rounds
description: Twelve-round verification for PostgreSQL and Supabase migrations. Use before writing, while writing, and after applying any migration, row-level security policy, database function, trigger or GRANT. Catches cross-tenant leaks through SECURITY DEFINER functions, policy recursion, revoked policy helpers, single-use-token races, functions that exist but cannot run, and slow per-row policies — then proves the fix on a throwaway container, in both directions.
---

# Migration Rounds

A migration that applies is not a migration that works. These rounds exist because
those are two different claims, and the second one is routinely shipped on the
strength of the first.

The full checklists for every round are in [ROUNDS.md](ROUNDS.md). This file is the
procedure and the rules that matter most.

---

## Step 0 — Measure, never recall

Before naming the file:

```bash
date -u +%Y%m%d%H%M%S                      # or: Get-Date -Format yyyyMMddHHmmss
```

```sql
SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 3;
```

The filename is the real clock, and it must sort **after** the newest applied
version. A round or invented timestamp (`...180000` written at 13:55) is not a
cosmetic mistake: every migration written before that hour is now blocked, and the
applied one cannot be edited to fix it.

**The general rule: never write down a fact about the database that you did not
measure in this session.** The clock, the latest applied version, a table's columns,
the values a CHECK constraint admits — read them. A confident guess and a measurement
look identical in a diff.

---

## The rounds

| Round | Question it answers |
|---|---|
| **0** Backup | If this destroys something, can it be put back? Back up tables, function bodies and policies before any DROP, TRUNCATE or `CREATE OR REPLACE`. |
| **1** Logic | Is the logic right — NULLs, arrays, division, conflicts, time zones, cascades? |
| **2** Names | Does every table, column, function and CHECK value match what the database actually has? |
| **3** Compatibility | Do types, NOT NULLs, constraints, triggers and foreign keys line up with what exists? |
| **4** RLS performance | Is every `auth.uid()` wrapped as `(SELECT auth.uid())`, every policy `TO` a role, every policy column indexed? |
| **5** Line by line | Has every line been checked against the live catalog — not memory? |
| **6** Security | Does every access decision trace to the session, never to a parameter? |
| **7** Quality | Pagination, deterministic ordering, volatility, `NOT EXISTS`, half-open time ranges? |
| **8** Concurrency | No queries in loops, no SELECT-then-UPDATE, nothing that breaks under a transaction pooler? |
| **9** Modularity | Can this be understood, changed and dropped on its own? |
| **10** Grant surface | Who can execute each function, and what can an attacker do with only the public key? |
| **11** Exploit reproduction | Was the original exploit run before the fix, and watched failing after it? |
| **12** Behaviour proof | Does it BEHAVE correctly, as a real user, on a real Postgres — and did the same test fail before the fix? |

Fix every issue the moment it is found. Do not advance a round with anything open.
After Round 9, re-read the whole file assuming it is wrong.

---

## Round 12 — the behaviour proof

**Rounds 0–11 cannot test row-level security, and neither can your migration.** A
migration runs as the table owner, and the owner is not subject to RLS unless the
table forces it. Setting `request.jwt.claims` changes who you *appear* to be; it does
not change *whether RLS applies*. Assert **structure** inside the migration. Prove
**behaviour** here.

1. **A throwaway container at production's major version.** Bound to nothing, or to
   `127.0.0.1` only. Never point any of this at production.
2. **A fixture traced to the real schema** — columns, and also CHECK constraints,
   UNIQUE constraints, generated columns, triggers and grants. Give it *worst-case*
   default privileges (new tables granted to the browser roles), so RLS is the only
   thing between a user and every row. **A fixture laxer than production is the only
   kind that ships bugs.**
3. **Apply the pending migrations in shipping order, on one database.** Two migrations
   that each pass alone can still collide. Count the `OK:` assertions you saw, from
   both stdout *and* stderr — `RAISE NOTICE` travels on stderr.
4. **A behaviour matrix, as `authenticated`.** One transaction, `ROLLBACK` at the end,
   `SET LOCAL ROLE authenticated` and the caller's claims set. Cast a viewer for every
   distinct verdict the rule makes, and assert a positive **and** a negative for every
   rule.
5. **Run the same matrix on the database without the fix, and require it to fail.** A
   matrix that passes on the broken database cannot see the hole, and the green run will
   never tell you. Record both figures — e.g. `12/12 after, 5/12 failing before`.
6. **The grant matrix.** Every SECURITY DEFINER function has a pinned `search_path`;
   every helper a policy calls is executable by the querying role; destructive functions
   are not executable by the browser roles at all. And **call** every new function — do
   not only look it up in `pg_proc`.
7. **After deploy, over real HTTP**, through the path the screen actually uses. A policy
   protects only the callers that go through it.

Paste this into the migration header and fill it in:

```
BEHAVIOUR PROOF
  1 container  postgres:<major> on a throwaway, network-isolated container   [ ]
  2 fixture    traced to information_schema + pg_constraint + pg_trigger     [ ]
  3 replay     shipping order, one database, n OK: assertions seen           [ ]
  4 matrix     <feature>-matrix.sql as authenticated  → n/n                  [ ]
  5 inverse    same matrix without this migration     → m/n FAIL             [ ]
  6 grants     definer · pinned search_path · helpers executable · called    [ ]
  7 http       after deploy, through the path the UI uses                    [ ]
```

### See it work

`proof/run.sh` runs this whole round against six real defect classes on a throwaway,
network-isolated Postgres. Each case has a broken migration, a fixed one and one
matrix; the harness requires the matrix to **catch** the broken version and **pass**
the fixed one, and for two cases shows that the same matrix run as the table owner
gives the same answer for both — which is why step 4 says `authenticated`.

```bash
bash proof/run.sh
```

---

## The rules that cost the most to learn

- **A SECURITY DEFINER function is a hole in RLS by definition.** Its body is entirely
  responsible for its own authorisation. A row filter written `p_x IS NULL OR ...` is an
  open door whenever the client can omit `p_x`. *(proof case 01)*
- **A policy must never read its own table.** Ask a SECURITY DEFINER helper instead —
  one definition of membership, used by every policy. *(case 02)*
- **A helper called from a policy must stay executable by the querying role.** A policy
  runs as the caller. "Tightening" the helper's grants breaks every query for every user.
  *(case 03)*
- **Single-use tokens are claimed by the UPDATE, never by SELECT-then-UPDATE.** And
  `expires_at < now()` is NULL, not TRUE, when the expiry is NULL. *(case 04)*
- **`CREATE OR REPLACE` succeeding proves nothing for PL/pgSQL.** Names resolve at run
  time. Call the function in the migration's own DO block. Schema-qualify extension
  functions rather than widening a definer's `search_path`. *(case 05)*
- **Wrap `auth.uid()` in a subquery in every policy.** Bare, it is evaluated per row.
  *(case 06)*
- **`BEGIN; … COMMIT;` in a migration file may be decoration.** Some tools apply a file
  statement by statement, so a failure part-way leaves everything before it live. Where
  atomicity matters, put the change and its assertion in **one** `DO` block. Order the
  rest so a partial apply can be repaired by re-running.
- **When an apply goes red, read what landed** — the catalog and the migrations table —
  never infer it from the exit code.
- **Assert on the message you raised, not the SQLSTATE.** A missing grant, RLS and your
  own guard all speak `42501`.
- **A missing signal is not a good signal.** A check that sees nothing must say
  "nothing checked", never "pass". A detector must be proven to see its own signal at
  all.
- **Where a lifetime is policy, it belongs in the function**, not in an argument every
  caller gets its own chance to get wrong.
- **Never edit a migration that has been applied anywhere.** Write a new one.
