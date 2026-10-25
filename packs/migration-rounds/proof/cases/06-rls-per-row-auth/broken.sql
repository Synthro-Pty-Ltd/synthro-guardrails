-- BROKEN: a correct policy that is slow on every row.
--
-- `auth.uid()` is STABLE, not a constant, so a bare call in a policy is
-- evaluated once PER ROW the query touches — parsing the session's JWT claims
-- each time. The answers are right. The query just gets slower with every row
-- the table grows by, and nothing fails until a page times out.
CREATE TABLE public.activity (
  id           bigserial PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  actor_id     uuid NOT NULL,
  action       text NOT NULL,
  at           timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY activity_select ON public.activity FOR SELECT TO authenticated
  USING (actor_id = auth.uid());

INSERT INTO public.activity (workspace_id, actor_id, action)
SELECT CASE WHEN i % 3 = 1 THEN '00000000-0000-4000-b000-00000000000b'::uuid
            ELSE '00000000-0000-4000-b000-00000000000a'::uuid END,
       CASE i % 3 WHEN 0 THEN '00000000-0000-4000-a000-00000000000a'::uuid
                  WHEN 1 THEN '00000000-0000-4000-a000-00000000000b'::uuid
                  ELSE        '00000000-0000-4000-a000-00000000000c'::uuid END,
       'viewed'
FROM generate_series(1, 200000) AS i;
ANALYZE public.activity;
