// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.
//
// Migrations are embedded in the binary so the same container image runs both
// the API (`server serve`) and the Kubernetes migration Job (`server migrate`).

import 'dart:io';

import 'package:postgres/postgres.dart';

/// Ordered, append-only list of schema versions. Never edit an applied entry;
/// add a new one instead.
const Map<int, String> migrations = {
  1: r'''
CREATE TABLE tenants (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  plan        text NOT NULL DEFAULT 'trial',
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  email            text NOT NULL,
  password_hash    text NOT NULL,
  name             text NOT NULL,
  role             text NOT NULL CHECK (role IN ('owner', 'admin', 'viewer')),
  failed_attempts  integer NOT NULL DEFAULT 0,
  locked_until     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email));
CREATE INDEX users_tenant_idx ON users (tenant_id);

CREATE TABLE sessions (
  token_hash  text PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE contacts (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  first_name          text NOT NULL,
  last_name           text NOT NULL,
  title               text,
  job_function        text,
  company_name        text,
  work_email          text,
  personal_email      text,
  phone_number        text,
  products            text,
  escalation_contact  boolean NOT NULL DEFAULT false,
  created_by          uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX contacts_tenant_name_idx ON contacts (tenant_id, last_name, first_name);

CREATE TABLE audit_logs (
  id           bigserial PRIMARY KEY,
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id      uuid,
  action       text NOT NULL,
  entity_type  text,
  entity_id    uuid,
  details      jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_tenant_time_idx ON audit_logs (tenant_id, created_at DESC);
''',
  2: r'''
-- Row-Level Security: the database itself refuses cross-tenant reads/writes,
-- even if application code forgets a WHERE clause. Fails closed: when
-- app.tenant_id is unset, the policy compares against NULL and matches nothing.
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON contacts
  USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
  WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON audit_logs
  USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
  WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
''',
};

/// Least-privilege grants for the runtime role. Re-applied on every migrate
/// run so they also cover a `drakkar_app` user created after the tables.
const String appRoleGrants = r'''
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'drakkar_app') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON tenants, users, sessions, contacts TO drakkar_app;
    GRANT SELECT, INSERT ON audit_logs TO drakkar_app;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO drakkar_app;
  ELSE
    RAISE WARNING 'role drakkar_app does not exist yet; create it, then re-run migrate';
  END IF;
END
$$;
''';

/// Applies pending migrations. Safe to run concurrently: an advisory lock
/// makes a second runner wait instead of racing.
Future<void> runMigrations(Pool pool) async {
  await pool.withConnection((conn) async {
    await conn.execute('SELECT pg_advisory_lock(7302026)');
    try {
      await conn.execute(
        'CREATE TABLE IF NOT EXISTS schema_migrations ('
        'version integer PRIMARY KEY, '
        'applied_at timestamptz NOT NULL DEFAULT now())',
      );
      for (final entry in migrations.entries) {
        final done = await conn.execute(
          Sql.named('SELECT 1 FROM schema_migrations WHERE version = CAST(@v AS integer)'),
          parameters: {'v': entry.key},
        );
        if (done.isNotEmpty) continue;
        await conn.runTx((tx) async {
          await tx.execute(entry.value, queryMode: QueryMode.simple);
          await tx.execute(
            Sql.named('INSERT INTO schema_migrations (version) VALUES (CAST(@v AS integer))'),
            parameters: {'v': entry.key},
          );
        });
        stdout.writeln('{"level":"info","msg":"applied migration ${entry.key}"}');
      }
      await conn.execute(appRoleGrants, queryMode: QueryMode.simple);
      stdout.writeln('{"level":"info","msg":"migrations complete"}');
    } finally {
      await conn.execute('SELECT pg_advisory_unlock(7302026)');
    }
  });
}
