-- Fixture: a small multi-tenant schema shaped like a hosted Supabase project.
--
-- Two choices here are deliberate, and both make the fixture HARSHER than a
-- default Postgres, never laxer:
--
--   1. Worst-case default privileges. Every new table, sequence and function in
--      `public` is granted to `anon` and `authenticated`, the way a hosted
--      Supabase project does it. Row-level security is therefore the ONLY thing
--      standing between a signed-in user and every row. A fixture that grants
--      less than production hides exactly the bugs this harness exists to find.
--
--   2. `auth.uid()` reads the same `request.jwt.claims` setting the real one
--      does, and is STABLE like the real one, so policy planning behaves the
--      same way (see case 06).
--
-- Every id is synthetic. Two workspaces, three people:
--   alice  owns workspace A
--   carol  is a member of workspace A
--   bob    owns workspace B

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;

GRANT USAGE ON SCHEMA auth, public, extensions TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;

CREATE TABLE public.workspaces (
  id    uuid PRIMARY KEY,
  name  text NOT NULL
);

CREATE TABLE public.members (
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL,
  role         text NOT NULL CHECK (role IN ('owner', 'member')),
  PRIMARY KEY (workspace_id, user_id)
);
CREATE INDEX members_user_id_idx ON public.members(user_id);

CREATE TABLE public.notes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  author_id    uuid NOT NULL,
  body         text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notes_workspace_id_idx ON public.notes(workspace_id);

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.members    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes      ENABLE ROW LEVEL SECURITY;

-- The one membership helper every policy uses. It reads the caller from the
-- session, never from a parameter, so it cannot be asked about somebody else.
-- SECURITY DEFINER so that a policy on `members` can call it without the policy
-- reading `members` itself (case 02 is what happens otherwise).
CREATE OR REPLACE FUNCTION public.is_workspace_member(p_workspace_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.workspace_id = p_workspace_id
      AND m.user_id = (SELECT auth.uid())
  )
$$;
REVOKE EXECUTE ON FUNCTION public.is_workspace_member(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_workspace_member(uuid) TO authenticated;

CREATE POLICY workspaces_select ON public.workspaces FOR SELECT TO authenticated
  USING (public.is_workspace_member(id));

CREATE POLICY members_select ON public.members FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id));

CREATE POLICY notes_select ON public.notes FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id));

CREATE POLICY notes_insert ON public.notes FOR INSERT TO authenticated
  WITH CHECK (public.is_workspace_member(workspace_id) AND author_id = (SELECT auth.uid()));

INSERT INTO public.workspaces (id, name) VALUES
  ('00000000-0000-4000-b000-00000000000a', 'Workspace A'),
  ('00000000-0000-4000-b000-00000000000b', 'Workspace B');

INSERT INTO public.members (workspace_id, user_id, role) VALUES
  ('00000000-0000-4000-b000-00000000000a', '00000000-0000-4000-a000-00000000000a', 'owner'),
  ('00000000-0000-4000-b000-00000000000a', '00000000-0000-4000-a000-00000000000c', 'member'),
  ('00000000-0000-4000-b000-00000000000b', '00000000-0000-4000-a000-00000000000b', 'owner');

INSERT INTO public.notes (workspace_id, author_id, body) VALUES
  ('00000000-0000-4000-b000-00000000000a', '00000000-0000-4000-a000-00000000000a', 'A: launch plan'),
  ('00000000-0000-4000-b000-00000000000a', '00000000-0000-4000-a000-00000000000c', 'A: budget draft'),
  ('00000000-0000-4000-b000-00000000000b', '00000000-0000-4000-a000-00000000000b', 'B: private roadmap'),
  ('00000000-0000-4000-b000-00000000000b', '00000000-0000-4000-a000-00000000000b', 'B: salary notes');
