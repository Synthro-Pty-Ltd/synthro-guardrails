-- Behaviour matrix: call the function as a real signed-in user.
BEGIN;
SET LOCAL ROLE :"as_role";
DO $$
DECLARE
  alice uuid := '00000000-0000-4000-a000-00000000000a';
  total int := 0;
  fails int := 0;
  a     text;
  b     text;
BEGIN
  PERFORM set_config('request.jwt.claims',
          json_build_object('sub', alice, 'role', 'authenticated')::text, true);

  total := total + 1;
  BEGIN
    a := public.new_invite_token();
    IF a ~ '^[0-9a-f]{32}$' THEN RAISE NOTICE 'ok    new_invite_token() runs and returns 32 hex characters';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  new_invite_token() returned %', a; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  new_invite_token() raised % %', SQLSTATE, SQLERRM;
  END;

  total := total + 1;
  BEGIN
    a := public.new_invite_token();
    b := public.new_invite_token();
    IF a IS DISTINCT FROM b THEN RAISE NOTICE 'ok    two calls return two different tokens';
    ELSE fails := fails + 1; RAISE NOTICE 'FAIL  two calls returned the same token'; END IF;
  EXCEPTION WHEN OTHERS THEN
    fails := fails + 1; RAISE NOTICE 'FAIL  second call raised % %', SQLSTATE, SQLERRM;
  END;

  RAISE NOTICE 'RESULT % %/%', CASE WHEN fails = 0 THEN 'CLEAN' ELSE 'DEFECT' END, total - fails, total;
END $$;
ROLLBACK;
