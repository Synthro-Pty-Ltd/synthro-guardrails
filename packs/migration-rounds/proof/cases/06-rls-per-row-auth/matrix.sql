-- Behaviour matrix: same answer, and the caller is resolved once per query.
--
-- The timing is printed for information only. The assertion is on the PLAN,
-- because a plan is deterministic and a stopwatch on a shared CI runner is not.
BEGIN;
SET LOCAL ROLE :"as_role";
DO $$
DECLARE
  alice   uuid := '00000000-0000-4000-a000-00000000000a';
  total   int := 0;
  fails   int := 0;
  n       int;
  plan    text := '';
  r       record;
  started timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claims',
          json_build_object('sub', alice, 'role', 'authenticated')::text, true);

  total := total + 1;
  BEGIN
    started := clock_timestamp();
    SELECT count(*) INTO n FROM public.activity;
    RAISE NOTICE 'info  counting alice''s rows took % ms',
      round(extract(epoch FROM clock_timestamp() - started) * 1000);
    IF n = 66666 THEN RAISE NOTICE 'ok    alice sees exactly her own 66666 rows of 200000';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  alice should see 66666 rows, got %', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  counting raised % %', SQLSTATE, SQLERRM;
  END;

  total := total + 1;
  BEGIN
    FOR r IN EXECUTE 'EXPLAIN SELECT count(*) FROM public.activity' LOOP
      plan := plan || r."QUERY PLAN" || E'\n';
    END LOOP;
    IF plan ~* 'InitPlan' THEN RAISE NOTICE 'ok    the caller is resolved once per query (InitPlan)';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  auth.uid() is evaluated once per row (no InitPlan in the plan)'; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  EXPLAIN raised % %', SQLSTATE, SQLERRM;
  END;

  RAISE NOTICE 'RESULT % %/%', CASE WHEN fails = 0 THEN 'CLEAN' ELSE 'DEFECT' END, total - fails, total;
END $$;
ROLLBACK;
