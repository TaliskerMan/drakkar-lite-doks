// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'package:postgres/postgres.dart';

import 'config.dart';

/// Thin wrapper around a Postgres connection pool.
///
/// Each API pod holds its own pool, so total connections to the database are
/// roughly `replicas × maxConnections`. Keep that under the managed
/// database's limit: the 1 GiB DigitalOcean plan allows 22, and 5 pods × 3 = 15.
/// Beyond that, use a bigger plan or DigitalOcean's PgBouncer connection pool.
class Db {
  Db(this.pool);

  factory Db.open(Config config, {int maxConnections = 3}) {
    return Db(
      Pool.withEndpoints(
        [config.endpoint],
        settings: PoolSettings(
          maxConnectionCount: maxConnections,
          sslMode: config.sslMode,
        ),
      ),
    );
  }

  final Pool pool;

  /// Used by the readiness probe.
  Future<void> ping() async {
    await pool.execute('SELECT 1');
  }

  /// Runs [fn] inside a transaction with the tenant set for Row-Level Security.
  ///
  /// `set_config(..., true)` is transaction-scoped (like `SET LOCAL`), so the
  /// setting can never leak to another request that reuses the connection.
  Future<T> inTenant<T>(String tenantId, Future<T> Function(TxSession tx) fn) {
    return pool.runTx((tx) async {
      await setTenant(tx, tenantId);
      return fn(tx);
    });
  }

  /// Sets the RLS tenant for the current transaction.
  static Future<void> setTenant(TxSession tx, String tenantId) async {
    await tx.execute(
      Sql.named("SELECT set_config('app.tenant_id', @tid, true)"),
      parameters: {'tid': tenantId},
    );
  }

  Future<void> close() => pool.close();
}
