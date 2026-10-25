-- BROKEN: a function that exists and cannot run.
--
-- `gen_random_bytes()` comes from pgcrypto, which lives in the `extensions`
-- schema. The function pins `search_path = public, pg_temp` (correctly, for a
-- SECURITY DEFINER function), so the unqualified name cannot be found.
-- PL/pgSQL does not resolve names until the line runs, so CREATE succeeds.
--
-- And the migration "proves" itself the way most migrations do — by checking
-- the function exists. The assertion passes. Every call will raise 42883.
CREATE OR REPLACE FUNCTION public.new_invite_token()
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RETURN encode(gen_random_bytes(16), 'hex');
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'new_invite_token') THEN
    RAISE EXCEPTION 'new_invite_token was not created';
  END IF;
  RAISE NOTICE 'OK: new_invite_token exists';
END $$;
