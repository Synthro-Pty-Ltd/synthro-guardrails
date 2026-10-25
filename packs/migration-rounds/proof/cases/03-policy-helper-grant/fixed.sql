-- FIXED: close the roles that never query these tables, keep the one that does.
--
-- A helper that a policy calls must stay executable by every role the policy
-- applies to. It is safe to leave it executable because it answers only one
-- question — "am I a member of this workspace?" — about the caller and nobody
-- else.
REVOKE EXECUTE ON FUNCTION public.is_workspace_member(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_workspace_member(uuid) TO authenticated;
