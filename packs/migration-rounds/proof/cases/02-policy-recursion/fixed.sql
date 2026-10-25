-- FIXED: the policy asks the membership helper instead of reading its own table.
--
-- `is_workspace_member()` is SECURITY DEFINER and owned by the table owner, so
-- its read of `members` is not filtered by the policy that called it. One
-- definition of membership, in one place, used by every policy.
DROP POLICY IF EXISTS members_select ON public.members;
CREATE POLICY members_select ON public.members FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id));
