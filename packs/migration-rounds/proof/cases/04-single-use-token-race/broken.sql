-- BROKEN: a single-use invite redeemed by SELECT-then-UPDATE.
--
-- Two defects that read as correct code:
--
--   1. The check and the claim are separate statements. Two requests that
--      arrive together both read `used_at IS NULL`, both pass, and both redeem.
--      The pg_sleep below only widens the window so the race is reproducible
--      on every run; in production the window is network jitter, and it is
--      enough. The fixed version sleeps for exactly as long.
--
--   2. `v_expires < now()` is NULL, not TRUE, when expires_at is NULL, so an
--      invite created without an expiry never expires.
CREATE TABLE public.invites (
  token        text PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  used_at      timestamptz,
  expires_at   timestamptz
);
CREATE TABLE public.redemptions (
  id           bigserial PRIMARY KEY,
  token        text NOT NULL,
  redeemed_by  uuid NOT NULL,
  redeemed_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.invites     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.redemptions ENABLE ROW LEVEL SECURITY;

INSERT INTO public.invites (token, workspace_id, expires_at) VALUES
  ('race-1',    '00000000-0000-4000-b000-00000000000a', now() + interval '1 hour'),
  ('no-expiry', '00000000-0000-4000-b000-00000000000a', NULL);

CREATE OR REPLACE FUNCTION public.redeem_invite(p_token text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_used    timestamptz;
  v_expires timestamptz;
BEGIN
  SELECT used_at, expires_at INTO v_used, v_expires
  FROM public.invites WHERE token = p_token;

  IF NOT FOUND OR v_used IS NOT NULL OR v_expires < now() THEN
    RETURN false;
  END IF;

  PERFORM pg_sleep(0.5);

  UPDATE public.invites SET used_at = now() WHERE token = p_token;
  INSERT INTO public.redemptions (token, redeemed_by) VALUES (p_token, (SELECT auth.uid()));
  RETURN true;
END $$;
