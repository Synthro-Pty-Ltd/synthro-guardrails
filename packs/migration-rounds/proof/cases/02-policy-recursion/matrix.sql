-- Behaviour matrix: reading `members` as a real signed-in user, both directions.
BEGIN;
SET LOCAL ROLE :"as_role";
DO $$
DECLARE
  alice uuid := '00000000-0000-4000-a000-00000000000a';
  ws_a  uuid := '00000000-0000-4000-b000-00000000000a';
  ws_b  uuid := '00000000-0000-4000-b000-00000000000b';
  total int := 0;
  fails int := 0;
  n     int;
BEGIN
  PERFORM set_config('request.jwt.claims',
          json_build_object('sub', alice, 'role', 'authenticated')::text, true);

  total := total + 1;
  BEGIN
    SELECT count(*) INTO n FROM public.members WHERE workspace_id = ws_a;
    IF n = 2 THEN RAISE NOTICE 'ok    alice sees both members of her workspace';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  alice should see 2 members of A, got %', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  reading own members raised % %', SQLSTATE, SQLERRM;
  END;

  total := total + 1;
  BEGIN
    SELECT count(*) INTO n FROM public.members WHERE workspace_id = ws_b;
    IF n = 0 THEN RAISE NOTICE 'ok    alice sees no members of another workspace';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  alice sees % members of workspace B', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  reading foreign members raised % %', SQLSTATE, SQLERRM;
  END;

  RAISE NOTICE 'RESULT % %/%', CASE WHEN fails = 0 THEN 'CLEAN' ELSE 'DEFECT' END, total - fails, total;
END $$;
ROLLBACK;
