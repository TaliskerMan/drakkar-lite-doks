-- Runs once, when the local Postgres volume is first created.
-- Mirrors `doctl databases user create <db-id> drakkar_app` on DigitalOcean:
-- a login role that does NOT own the tables, so Row-Level Security applies to it.
CREATE ROLE drakkar_app LOGIN PASSWORD 'app-dev-only';
GRANT CONNECT ON DATABASE drakkar TO drakkar_app;
GRANT USAGE ON SCHEMA public TO drakkar_app;
