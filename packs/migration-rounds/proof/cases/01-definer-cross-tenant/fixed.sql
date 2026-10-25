-- FIXED: the function checks who is calling, inside its own body.
--
-- A SECURITY DEFINER function is a hole in row-level security by definition, so
-- its body is 100% responsible for its own authorisation. The caller comes from
-- the session (`auth.uid()`), never from a parameter, and the optional filter
-- can only NARROW what the caller is already allowed to see.
CREATE OR REPLACE FUNCTION public.list_notes(p_workspace_id uuid DEFAULT NULL)
RETURNS SETOF public.notes
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT n.*
  FROM public.notes n
  WHERE n.workspace_id IN (
          SELECT m.workspace_id FROM public.members m
          WHERE m.user_id = (SELECT auth.uid())
        )
    AND (p_workspace_id IS NULL OR n.workspace_id = p_workspace_id)
  ORDER BY n.created_at DESC, n.id DESC
  LIMIT 100
$$;
