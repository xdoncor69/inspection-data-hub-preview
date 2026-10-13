-- Applied after inspecting live grants. No rows are changed.
-- RLS does not restrict TRUNCATE; client roles do not need DDL-like privileges.
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.inspection_snapshots FROM authenticated, anon, PUBLIC;
