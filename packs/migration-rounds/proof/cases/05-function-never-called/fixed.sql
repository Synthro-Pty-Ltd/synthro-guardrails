-- FIXED: qualify the extension function, and make the migration CALL what it
-- created.
--
-- Do not fix this by widening the search_path of a SECURITY DEFINER function;
-- name the schema instead. And an assertion that a function exists is not an
-- assertion that it works: call it, inside the migration, and check the answer.
CREATE OR REPLACE FUNCTION public.new_invite_token()
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RETURN encode(extensions.gen_random_bytes(16), 'hex');
END $$;

DO $$
DECLARE
  v text := public.new_invite_token();
BEGIN
  IF v !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'new_invite_token returned %, expected 32 hex characters', v;
  END IF;
  RAISE NOTICE 'OK: new_invite_token runs and returns 32 hex characters';
END $$;
