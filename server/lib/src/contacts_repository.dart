// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.
//
// Server-side replacement for Valhalla's contact CRUD in DatabaseService.
// Every query filters on tenant_id AND runs under Row-Level Security.

import 'package:drakkar_core/drakkar_core.dart';
import 'package:postgres/postgres.dart';

import 'audit.dart';
import 'db.dart';
import 'http.dart';

const String _columns = 'CAST(id AS text), first_name, last_name, title, job_function, '
    'company_name, work_email, personal_email, phone_number, products, '
    'escalation_contact, created_at, updated_at';

class ContactsRepository {
  ContactsRepository(this.db);

  final Db db;

  Future<List<Contact>> list(Principal who, {String query = '', int limit = 200}) {
    return db.inTenant(who.tenantId, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'SELECT $_columns FROM contacts '
          'WHERE tenant_id = CAST(@tenant AS uuid) '
          "AND (CAST(@q AS text) = '' OR first_name ILIKE @p OR last_name ILIKE @p "
          'OR company_name ILIKE @p OR work_email ILIKE @p) '
          'ORDER BY last_name, first_name '
          'LIMIT CAST(@limit AS integer)',
        ),
        parameters: {
          'tenant': who.tenantId,
          'q': query,
          'p': likePattern(query),
          'limit': limit,
        },
      );
      return rows.map(_fromRow).toList();
    });
  }

  Future<Contact?> get(Principal who, String id) {
    return db.inTenant(who.tenantId, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'SELECT $_columns FROM contacts '
          'WHERE id = CAST(@id AS uuid) AND tenant_id = CAST(@tenant AS uuid)',
        ),
        parameters: {'id': id, 'tenant': who.tenantId},
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    });
  }

  Future<Contact> create(Principal who, Contact c) {
    return db.inTenant(who.tenantId, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO contacts (tenant_id, first_name, last_name, title, job_function, '
          'company_name, work_email, personal_email, phone_number, products, '
          'escalation_contact, created_by) '
          'VALUES (CAST(@tenant AS uuid), @first, @last, @title, @function, @company, '
          '@work, @personal, @phone, @products, @escalation, CAST(@user AS uuid)) '
          'RETURNING $_columns',
        ),
        parameters: {
          'tenant': who.tenantId,
          'first': c.firstName,
          'last': c.lastName,
          'title': c.title,
          'function': c.function,
          'company': c.companyName,
          'work': c.workEmail,
          'personal': c.personalEmail,
          'phone': c.phoneNumber,
          'products': c.products,
          'escalation': c.escalationContact,
          'user': who.userId,
        },
      );
      final created = _fromRow(rows.first);
      await writeAudit(tx,
          tenantId: who.tenantId,
          userId: who.userId,
          action: 'CREATE',
          entityType: 'contact',
          entityId: created.id);
      return created;
    });
  }

  /// Returns false when the contact does not exist in the caller's tenant.
  Future<bool> delete(Principal who, String id) {
    return db.inTenant(who.tenantId, (tx) async {
      final result = await tx.execute(
        Sql.named(
          'DELETE FROM contacts WHERE id = CAST(@id AS uuid) AND tenant_id = CAST(@tenant AS uuid)',
        ),
        parameters: {'id': id, 'tenant': who.tenantId},
      );
      if (result.affectedRows == 0) return false;
      await writeAudit(tx,
          tenantId: who.tenantId,
          userId: who.userId,
          action: 'DELETE',
          entityType: 'contact',
          entityId: id);
      return true;
    });
  }

  static Contact _fromRow(ResultRow r) => Contact(
        id: r[0]! as String,
        firstName: r[1]! as String,
        lastName: r[2]! as String,
        title: r[3] as String?,
        function: r[4] as String?,
        companyName: r[5] as String?,
        workEmail: r[6] as String?,
        personalEmail: r[7] as String?,
        phoneNumber: r[8] as String?,
        products: r[9] as String?,
        escalationContact: r[10]! as bool,
        createdAt: r[11] as DateTime?,
        updatedAt: r[12] as DateTime?,
      );
}
