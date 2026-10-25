-- FIXED: the UPDATE is the claim.
--
-- Every condition — unused, not expired — lives in the UPDATE's WHERE clause.
-- When two requests race, the second blocks on the first one's row lock, then
-- re-evaluates the predicate against the committed row, matches nothing, and
-- returns false. An expiry written as `expires_at > now()` is NULL for a NULL
-- expiry, and NULL is not TRUE, so an invite without an expiry is refused.
--
-- Same tables, same seed, same 0.5s window as the broken version.
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
  v_token text;
BEGIN
  PERFORM pg_sleep(0.5);

  UPDATE public.invites
     SET used_at = now()
   WHERE token = p_token
     AND used_at IS NULL
     AND expires_at > now()
  RETURNING token INTO v_token;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  INSERT INTO public.redemptions (token, redeemed_by) VALUES (v_token, (SELECT auth.uid()));
  RETURN true;
END $$;
