# The rounds in full

Examples use a neutral multi-tenant schema: `workspaces`, `members`, `notes`, and a
membership helper `is_workspace_member(workspace_id)` that reads the caller from
`auth.uid()`. Replace the names with yours; keep the shape.

---

## Round 0 — Backup before you destroy

Run before any `DROP`, `TRUNCATE` or `CREATE OR REPLACE` of an existing object. Name
backups with the same measured timestamp as the migration.

| Destructive operation | Backup |
|---|---|
| DROP TABLE / TRUNCATE | `CREATE TABLE backup_<ts>_<name> AS SELECT * FROM <table>;` |
| DROP / REPLACE FUNCTION | `CREATE TABLE backup_<ts>_fn AS SELECT p.oid::regprocedure AS sig, pg_get_functiondef(p.oid) AS def, now() AS at FROM pg_proc p WHERE p.proname = '<fn>';` |
| DROP / REPLACE POLICY | `CREATE TABLE backup_<ts>_pol AS SELECT * FROM pg_policies WHERE tablename = '<table>';` |
| DROP INDEX | Record `pg_get_indexdef(oid)` in the migration header |
| DROP COLUMN / ALTER TYPE | Write the reverse migration in the header |

**Gate:** `SELECT count(*)` from the backup. Zero rows while the object exists means the
backup query is wrong — stop. Backups of function bodies and policies are sensitive:
enable RLS on them and grant them to nobody.

**Never rewrite a function from memory or from a truncated read.** Start from
`pg_get_functiondef(oid)`, record its length before and after, and treat a body that
*shrank* as a defect until you can explain every missing line.

---

## Round 1 — Logic

| Check | Wrong | Right |
|---|---|---|
| Transactions | Several writes that must succeed together, as separate statements | One function or one `DO` block |
| NULLs | `WHERE col <> val` on a nullable column | `IS DISTINCT FROM` |
| Arrays / JSON | `WHERE arr = val` | `val = ANY(arr)`, `@>`, `->>` |
| Division | `total / n` | `CASE WHEN n > 0 THEN total / n END` |
| Duplicates | INSERT that can collide | `ON CONFLICT (...) DO ...` |
| Time | `timestamp`, `now() + 7` | `timestamptz`, `now() + interval '7 days'` |
| Cascades | Assumed | Read `pg_constraint.confdeltype` and confirm it is what you want |
| Loops | A query inside `FOR` | One set-based query |
| Messages | `RAISE EXCEPTION 'Error'` | Say what failed and for which object |

Traps: `AND` where `OR` was meant in an access check · missing `RETURN` · missing
`LIMIT` on a large table · a `VOLATILE` function in a `WHERE` clause.

---

## Round 2 — Names

Read every name from the catalog; never type one from memory.

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = '<table>' ORDER BY ordinal_position;

SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.<table>'::regclass;            -- CHECK values are case-sensitive

SELECT p.oid::regprocedure FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = '<fn>';       -- the exact signature
```

A CHECK constraint's allowed values are the most common invented fact. Write a value
the constraint does not admit and the migration passes locally against a lax fixture,
then fails in production with `23514`.

---

## Round 3 — Compatibility

- Foreign key types match on both ends.
- Every `NOT NULL` column without a default appears in every INSERT.
- Existing triggers are not duplicated, and you know what each one does to your rows —
  a trigger can silently rewrite or skip the row your test depends on.
- Cross-schema names are qualified (`storage.objects`, `extensions.digest`).
- Every new foreign key column is indexed.
- Every function you call exists, with the signature you are calling.
- **Reference data a migration reads must be created by a migration**, never by seed
  data. Seeds usually run after migrations; a migration that needs a seeded row cannot
  build a database from empty, including the one you restore into after a disaster.

---

## Round 4 — RLS performance

| Check | Rule |
|---|---|
| `auth.uid()` | Always `(SELECT auth.uid())` in a policy — evaluated once per query, not once per row |
| One policy per command | Never two permissive policies for the same table, role and command; combine with `OR` |
| `FOR ALL` | Do not mix it with per-command policies on the same table and role |
| `USING` / `WITH CHECK` | `USING` decides which rows are visible; `WITH CHECK` decides which rows may be written. UPDATE needs both |
| `TO` role | Every policy names its role. Omitting it means `PUBLIC` |
| Indexes | Every column a policy filters on is indexed; on an existing table, `CREATE INDEX CONCURRENTLY`, outside a transaction |
| Views | `WITH (security_invoker = true)`, or the view bypasses RLS |

---

## Round 5 — Line by line

For every line: the table exists in that schema, the column exists with that type and
nullability, the function exists with that signature, the INSERT supplies every
`NOT NULL`, the UPDATE satisfies every CHECK, the policy's table has RLS enabled. Stop at
the first wrong line, fix it, re-query, continue.

---

## Round 6 — Security

| # | Check |
|---|---|
| 1 | The tenant is derived from the session (`auth.uid()` → membership), never from a parameter |
| 2 | Every query inside a SECURITY DEFINER function filters by that server-derived tenant |
| 3 | No `EXECUTE format(..., <caller input>)` building identifiers |
| 4 | Access failures raise one opaque message, the same for every reason |
| 5 | `WHERE id = p_id` always also says `AND workspace_id = <verified tenant>` |
| 6 | Nullable comparisons in access checks use `IS DISTINCT FROM` — `= NULL` skips the check silently |
| 7 | Every new table: `ENABLE ROW LEVEL SECURITY`, and nothing readable until a policy says so |
| 8 | Recipients of a notification or message are looked up server-side, never passed in |
| 9 | Nothing returns `SELECT *` of a table holding personal data to a browser — name the columns |

---

## Round 7 — Quality

- Row-returning functions take a bounded limit (`LEAST(GREATEST(coalesce(p_limit, 50), 1), 500)`).
- Ordering ends with a unique tiebreaker: `ORDER BY created_at DESC, id DESC`.
- Read-only functions are `STABLE`. The default is `VOLATILE`.
- `NOT EXISTS`, never `NOT IN (subquery)` — one NULL in the subquery returns nothing.
- Time ranges are half-open: `>= start AND < end`, never `BETWEEN`.
- A function you cannot describe in one sentence without "and" is two functions.

---

## Round 8 — Concurrency

- No query inside a `FOR` or `WHILE` loop.
- No SELECT-then-UPDATE on anything two requests can touch at once: put the condition in
  the UPDATE and use `RETURNING` — the losing request re-evaluates against the committed
  row and matches nothing.
- Under a transaction-mode pooler, no session state: no `SET` (non-local), no `PREPARE`.
- Counters use sequences or `pg_advisory_xact_lock`, not read-modify-write.
- Housekeeping (cleanup deletes) belongs in a scheduled job, never on a request path.

---

## Round 9 — Modularity

1. One migration, one logical domain.
2. A new feature's data goes in its own table keyed to the parent, not in new columns on
   a wide core table.
3. Every new table and function can be dropped without breaking anything else.
4. Function calls form a tree, not a cycle.
5. Every membership or role check calls the one canonical helper. Never re-implement it
   inline — the inline copies drift, and the one that drifts is the leak.
6. No column does two jobs.
7. Every dependency is checked to exist at migration time.
8. Functions stay under ~200 lines; split at 400.
9. Names say exactly what a thing does.
10. Every migration starts with a header: what it creates, why, what it depends on, how
    to reverse it — and the behaviour-proof block from Round 12.

---

## Round 10 — Grant surface

Every function in an API-exposed schema that a browser role can execute is reachable
from the internet with only the public key. Its body is then entirely responsible for
its own authorisation.

| # | Rule |
|---|---|
| 1 | Revoke first, then grant: `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated;` then grant only the role that needs it |
| 2 | Destructive and administrative functions are not executable by browser roles at all |
| 3 | Identity is always `(SELECT auth.uid())`. A caller-supplied email or user id never decides who the caller is |
| 4 | Every id parameter is checked against the caller before it is used |
| 5 | No `LIKE` / `ILIKE` with caller input on a destructive path — `%` matches everything |
| 6 | Nothing logs a password, token, one-time code or hash |
| 7 | Anything that verifies a code or password is throttled — and the throttle counts *failures*, not attempts, so a shared office IP is not locked out by its own staff |
| 8 | Credentials are compared with a slow hash only; there is no plaintext branch |
| 9 | One message for every authentication failure; existence checks need auth or a throttle |
| 10 | A helper called from a policy stays executable by the role the policy applies to |

```sql
SELECT p.oid::regprocedure AS fn,
       p.prosecdef         AS definer,
       coalesce(array_to_string(p.proconfig, ','), 'NO search_path') AS config,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('<fn>', ...);
```

Ask of every function: *if I paste its URL into curl with only the public key, what can
I do?*

---

## Round 11 — Reproduce the exploit, then watch it fail

A security fix is a hypothesis until the original exploit has been run against it.

| # | Prove |
|---|---|
| 1 | The exploit worked **before** the fix (or the fix is for a bug that does not exist) |
| 2 | The same call, as the attacker's role, now fails |
| 3 | As tenant A, every id of tenant B is refused — never test only with your own ids |
| 4 | A plain member cannot promote themselves: re-read the row afterwards to confirm no partial write |
| 5 | The legitimate caller still succeeds |
| 6 | Server-side callers that bypass the check still work, and a browser caller cannot forge that bypass |
| 7 | The Round 10 grant query, re-run after the migration, matches intent |
| 8 | The Round 0 backup exists, is non-empty and is locked down |
| 9 | Every policy that was dropped and recreated still exists |
| 10 | Every caller of the changed object is listed in the header and still works |

```sql
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"<attacker-user-id>","role":"authenticated"}', true);
SELECT * FROM public.list_notes('<victim-workspace-id>');           -- expect: nothing
UPDATE public.members SET role = 'owner' WHERE user_id = '<attacker-user-id>';  -- expect: refused
ROLLBACK;
```

---

## Round 12 — Behaviour proof

See [SKILL.md](SKILL.md#round-12--the-behaviour-proof) and run `proof/run.sh` for a
working example.

---

## Self-critique

Re-read the whole file as if proving it wrong: commas, capitalisation, misspelled
names, missing semicolons, wrong quotes, `AND` for `OR`, a missing `RETURN`, a missing
`STABLE` or `SECURITY DEFINER`, a missing `search_path`.

## Summary to write when done

1. What was created, and why.
2. Rounds 0–12, each with its result.
3. Every issue found and how it was fixed.
4. The behaviour-proof figures, both directions.
5. What is still owed (usually step 7, after deploy).
