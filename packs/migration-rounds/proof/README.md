# The proof

`run.sh` starts a throwaway `postgres:17` container with no network, loads
[fixture.sql](fixture.sql) — two workspaces, three people, row-level security on, and
the worst-case default privileges a hosted Supabase project has — and then, for every
case:

1. applies `broken.sql` to a fresh copy and runs the matrix **as a signed-in user** —
   it must report the defect;
2. applies `fixed.sql` to another fresh copy and runs the same matrix — it must come
   back clean;
3. for cases marked `blind`, runs the matrix **as the table owner** against both — the
   two verdicts must be identical, which is the point: a test run as the owner cannot
   tell the broken database from the fixed one.

It exits 1 if any defect goes undetected, any fix is not clean, or any matrix produces
no verdict at all.

## The cases

| Case | The defect | Why it survives review | The fix |
|---|---|---|---|
| **01 definer-cross-tenant** | A SECURITY DEFINER list function filters with `p_workspace_id IS NULL OR …`. Omit the argument and you get every tenant's rows | It applies, and the table's own policies are correct and pass any test against the table | The body derives the caller's workspaces from `auth.uid()`; the parameter can only narrow that |
| **02 policy-recursion** | A policy on `members` that reads `members` → `42P17` for every user | It applies, and the owner (not subject to RLS) sees nothing wrong | The policy calls a SECURITY DEFINER membership helper |
| **03 policy-helper-grant** | Revoking EXECUTE on that helper from `authenticated` → `42501` on every query | It looks like hardening, and the owner can execute anything | Revoke from `PUBLIC` and `anon`, keep `authenticated` |
| **04 single-use-token-race** | Redeem by SELECT, then UPDATE. Two simultaneous requests both redeem. A NULL expiry never expires | Every single-request test passes | The UPDATE carries every condition and `RETURNING` decides the winner |
| **05 function-never-called** | A definer function pins `search_path` and calls an extension function unqualified → `42883` on every call | `CREATE` succeeds and the migration's "does it exist?" assertion passes | Qualify `extensions.gen_random_bytes`; the migration **calls** the function |
| **06 rls-per-row-auth** | `USING (actor_id = auth.uid())` evaluates the caller once per row | The answers are right; only the clock is wrong | `(SELECT auth.uid())` becomes an InitPlan, evaluated once |

Case 06 also prints how long the count took. On a laptop: about **208 ms broken, 25 ms
fixed** over 200,000 rows. The assertion is on the query plan, not the stopwatch,
because a plan is deterministic and a shared CI runner is not.

Case 04 fires its two requests from inside the container so they start within
milliseconds of each other. Both versions wait the same 0.5 s inside the function; the
broken one still lets both through.

## Writing your own case

Add a folder under `cases/` with:

- `broken.sql` — the migration as it would have shipped;
- `fixed.sql` — the migration as it should be;
- `matrix.sql` — one transaction, `SET LOCAL ROLE :"as_role";`, a positive **and** a
  negative check for every rule, ending with `RAISE NOTICE 'RESULT CLEAN|DEFECT n/m'`
  (or `matrix.sh`, for anything a single session cannot test);
- `blind` — optional, if a test run as the owner cannot see this defect.

Then run `run.sh`. Your matrix has to catch your broken version, or the case fails.
