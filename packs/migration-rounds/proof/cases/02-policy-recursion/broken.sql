-- BROKEN: a policy on `members` that reads `members`.
--
-- It looks like the obvious way to say "you can see the members of workspaces
-- you belong to". Postgres evaluates the policy for the subquery too, which
-- evaluates the policy again, and refuses with 42P17 (infinite recursion) —
-- for every signed-in user, on every query that touches the table.
--
-- The migration applies without complaint, and any test run as the table owner
-- passes, because the owner is not subject to row-level security at all.
DROP POLICY IF EXISTS members_select ON public.members;
CREATE POLICY members_select ON public.members FOR SELECT TO authenticated
  USING (
    workspace_id IN (
      SELECT m.workspace_id FROM public.members m
      WHERE m.user_id = (SELECT auth.uid())
    )
  );
