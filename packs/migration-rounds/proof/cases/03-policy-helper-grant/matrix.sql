-- Behaviour matrix: reading notes as a real signed-in user, both directions.
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
    SELECT count(*) INTO n FROM public.notes WHERE workspace_id = ws_a;
    IF n = 2 THEN RAISE NOTICE 'ok    alice reads the notes of her own workspace';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  alice should read 2 own notes, got %', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  reading own notes raised % %', SQLSTATE, SQLERRM;
  END;

  total := total + 1;
  BEGIN
    SELECT count(*) INTO n FROM public.notes WHERE workspace_id = ws_b;
    IF n = 0 THEN RAISE NOTICE 'ok    alice reads nothing from another workspace';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  alice reads % notes of workspace B', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  reading foreign notes raised % %', SQLSTATE, SQLERRM;
  END;

  RAISE NOTICE 'RESULT % %/%', CASE WHEN fails = 0 THEN 'CLEAN' ELSE 'DEFECT' END, total - fails, total;
END $$;
ROLLBACK;
