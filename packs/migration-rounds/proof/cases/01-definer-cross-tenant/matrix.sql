-- Behaviour matrix: list_notes() as a real signed-in user, both directions.
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

  -- positive: the legitimate caller still gets her own notes
  total := total + 1;
  BEGIN
    SELECT count(*) INTO n FROM public.list_notes() WHERE workspace_id = ws_a;
    IF n = 2 THEN RAISE NOTICE 'ok    alice lists her own workspace notes (%)', n;
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  alice should list 2 own notes, got %', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  alice own notes raised % %', SQLSTATE, SQLERRM;
  END;

  -- negative: nothing from another tenant when the filter is omitted
  total := total + 1;
  BEGIN
    SELECT count(*) INTO n FROM public.list_notes() WHERE workspace_id = ws_b;
    IF n = 0 THEN RAISE NOTICE 'ok    no foreign notes when the filter is omitted';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  alice received % notes from another workspace', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  omitted filter raised % %', SQLSTATE, SQLERRM;
  END;

  -- negative: nothing from another tenant when she asks for it by id
  total := total + 1;
  BEGIN
    SELECT count(*) INTO n FROM public.list_notes(ws_b);
    IF n = 0 THEN RAISE NOTICE 'ok    asking for another workspace by id returns nothing';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  asking for workspace B by id returned % notes', n; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  foreign id raised % %', SQLSTATE, SQLERRM;
  END;

  RAISE NOTICE 'RESULT % %/%', CASE WHEN fails = 0 THEN 'CLEAN' ELSE 'DEFECT' END, total - fails, total;
END $$;
ROLLBACK;
