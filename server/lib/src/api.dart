// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'package:drakkar_core/drakkar_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'audit.dart';
import 'auth_repository.dart';
import 'contacts_repository.dart';
import 'db.dart';
import 'http.dart';
import 'metrics.dart';
import 'middleware.dart';

/// Builds the complete request pipeline.
Handler buildHandler({required Db db, required Metrics metrics, String? corsOrigin}) {
  final auth = AuthRepository(db);
  final contacts = ContactsRepository(db);

  final router = Router(notFoundHandler: (Request _) => ApiException.notFound.toResponse())
    // --- Probes & metrics (not routed by the Gateway) ----------------------
    ..get('/healthz', (Request _) => Response.ok('ok'))
    ..get('/readyz', (Request _) async {
      try {
        await db.ping();
        return Response.ok('ready');
      } catch (_) {
        return Response(503, body: 'database unavailable');
      }
    })
    ..get('/metrics', (Request _) {
      return Response.ok(
        metrics.render(),
        headers: {'content-type': 'text/plain; version=0.0.4'},
      );
    })

    // --- Auth -----------------------------------------------------------------
    ..post('/v1/auth/signup', (Request request) async {
      final body = await readJson(request);
      final organization = requireString(body, 'organization', maxLength: 120);
      final name = requireString(body, 'name', maxLength: 120);
      final email = requireString(body, 'email', maxLength: 254).toLowerCase();
      final password = requireString(body, 'password', maxLength: 128);
      if (!isValidEmail(email)) throw ApiException.badRequest('email is not valid.');
      final weak = SecurityValidator.validatePasswordComplexity(password);
      if (weak != null) throw ApiException.badRequest(weak);
      final result = await auth.signup(
        organization: organization,
        name: name,
        email: email,
        password: password,
      );
      return jsonResponse(result.toJson(), status: 201);
    })
    ..post('/v1/auth/login', (Request request) async {
      final body = await readJson(request);
      final email = requireString(body, 'email', maxLength: 254).toLowerCase();
      final password = requireString(body, 'password', maxLength: 128);
      final result = await auth.login(email, password);
      return jsonResponse(result.toJson());
    })
    ..post('/v1/auth/logout', (Request request) async {
      final token = request.context['token'];
      if (token is String) await auth.logout(token);
      return Response(204);
    })
    ..get('/v1/auth/me', (Request request) {
      return jsonResponse(principalOf(request).toJson());
    })

    // --- Contacts -------------------------------------------------------------
    ..get('/v1/contacts', (Request request) async {
      final who = principalOf(request);
      final q = (request.url.queryParameters['q'] ?? '').trim();
      if (q.length > 100) throw ApiException.badRequest('q is too long.');
      final items = await contacts.list(who, query: q);
      return jsonResponse({
        'items': [for (final c in items) c.toJson()],
      });
    })
    ..post('/v1/contacts', (Request request) async {
      final who = requireWriter(request);
      final contact = Contact.fromJson(await readJson(request));
      final problems = contact.validate();
      if (problems.isNotEmpty) throw ApiException.badRequest(problems.join(' '));
      final created = await contacts.create(who, contact);
      return jsonResponse(created.toJson(), status: 201);
    })
    ..get('/v1/contacts/<id>', (Request request, String id) async {
      final who = principalOf(request);
      final contact = await contacts.get(who, requireUuid(id));
      if (contact == null) throw ApiException.notFound;
      return jsonResponse(contact.toJson());
    })
    ..delete('/v1/contacts/<id>', (Request request, String id) async {
      final who = requireWriter(request);
      final deleted = await contacts.delete(who, requireUuid(id));
      if (!deleted) throw ApiException.notFound;
      return Response(204);
    })

    // --- Audit log ------------------------------------------------------------
    ..get('/v1/audit-logs', (Request request) async {
      final who = requireWriter(request);
      final items = await db.inTenant(who.tenantId, (tx) => readAudit(tx));
      return jsonResponse({'items': items});
    });

  return const Pipeline()
      .addMiddleware(observe(metrics))
      .addMiddleware(cors(corsOrigin))
      .addMiddleware(authenticate(auth))
      .addHandler(router.call);
}
