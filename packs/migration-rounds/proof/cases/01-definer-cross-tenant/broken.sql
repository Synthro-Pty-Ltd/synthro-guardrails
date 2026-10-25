-- BROKEN: a SECURITY DEFINER list function whose only row filter is optional.
--
-- It runs as its owner, so row-level security never applies to it. The filter
-- `p_workspace_id IS NULL OR ...` is unconditionally TRUE whenever the caller
-- leaves the parameter out — which is exactly what a client listing "my notes"
-- does. Every signed-in user receives every workspace's notes.
--
-- Note what passes: it applies cleanly, the RLS policies on `notes` are correct
-- and would survive any test run directly against the table.
CREATE OR REPLACE FUNCTION public.list_notes(p_workspace_id uuid DEFAULT NULL)
RETURNS SETOF public.notes
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT n.*
  FROM public.notes n
  WHERE (p_workspace_id IS NULL OR n.workspace_id = p_workspace_id)
  ORDER BY n.created_at DESC, n.id DESC
  LIMIT 100
$$;
