-- FIXED: wrap the call in a scalar subquery.
--
-- `(SELECT auth.uid())` becomes an InitPlan: Postgres evaluates it once per
-- query and compares every row against the stored value. Same rows, same
-- answer, one evaluation. (The Supabase performance advisor reports the bare
-- form as `auth_rls_initplan`.)
CREATE TABLE public.activity (
  id           bigserial PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  actor_id     uuid NOT NULL,
  action       text NOT NULL,
  at           timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY activity_select ON public.activity FOR SELECT TO authenticated
  USING (actor_id = (SELECT auth.uid()));

INSERT INTO public.activity (workspace_id, actor_id, action)
SELECT CASE WHEN i % 3 = 1 THEN '00000000-0000-4000-b000-00000000000b'::uuid
            ELSE '00000000-0000-4000-b000-00000000000a'::uuid END,
       CASE i % 3 WHEN 0 THEN '00000000-0000-4000-a000-00000000000a'::uuid
                  WHEN 1 THEN '00000000-0000-4000-a000-00000000000b'::uuid
                  ELSE        '00000000-0000-4000-a000-00000000000c'::uuid END,
       'viewed'
FROM generate_series(1, 200000) AS i;
ANALYZE public.activity;
