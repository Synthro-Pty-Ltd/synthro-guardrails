-- BROKEN: "tightening" the grants on a function that a policy calls.
--
-- Revoking EXECUTE on a SECURITY DEFINER function from the browser roles looks
-- like prudent hardening and passes review. But a policy expression is
-- evaluated AS THE QUERYING ROLE, so the moment `authenticated` cannot execute
-- the helper, every query on every table whose policy calls it fails with 42501
-- — for every signed-in user, at once.
--
-- The owner can execute anything, so a test run as the owner never notices.
REVOKE EXECUTE ON FUNCTION public.is_workspace_member(uuid) FROM PUBLIC, anon, authenticated;
