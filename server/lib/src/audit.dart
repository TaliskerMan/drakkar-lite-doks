// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'dart:convert';

import 'package:postgres/postgres.dart';

/// Appends an audit entry inside the caller's transaction, so the audit row
/// and the change it describes commit (or roll back) together.
/// The transaction must already have the tenant set (see Db.setTenant).
Future<void> writeAudit(
  TxSession tx, {
  required String tenantId,
  required String action,
  String? userId,
  String? entityType,
  String? entityId,
  Map<String, Object?>? details,
}) async {
  await tx.execute(
    Sql.named(
      'INSERT INTO audit_logs (tenant_id, user_id, action, entity_type, entity_id, details) '
      'VALUES (CAST(@tenant AS uuid), CAST(@user AS uuid), @action, @etype, '
      'CAST(@eid AS uuid), CAST(@details AS jsonb))',
    ),
    parameters: {
      'tenant': tenantId,
      'user': userId,
      'action': action,
      'etype': entityType,
      'eid': entityId,
      'details': details == null ? null : jsonEncode(details),
    },
  );
}

/// Reads the most recent audit entries for the tenant set on [tx].
Future<List<Map<String, Object?>>> readAudit(TxSession tx, {int limit = 100}) async {
  final rows = await tx.execute(
    Sql.named(
      'SELECT a.id, CAST(a.user_id AS text), u.name, a.action, a.entity_type, '
      'CAST(a.entity_id AS text), CAST(a.details AS text), a.created_at '
      'FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id '
      'ORDER BY a.created_at DESC LIMIT CAST(@limit AS integer)',
    ),
    parameters: {'limit': limit},
  );
  return [
    for (final r in rows)
      {
        'id': r[0],
        'userId': r[1],
        'userName': r[2],
        'action': r[3],
        'entityType': r[4],
        'entityId': r[5],
        'details': r[6] == null ? null : jsonDecode(r[6]! as String),
        'createdAt': (r[7]! as DateTime).toUtc().toIso8601String(),
      },
  ];
}
