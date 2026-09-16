// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.
//
// Server-side version of Valhalla's AuthService + DatabaseService.login():
// bcrypt verification, lockout after repeated failures (now stored in the
// database, so it holds across pods and restarts), and opaque session tokens.

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

import 'audit.dart';
import 'db.dart';
import 'http.dart';

/// A newly issued session.
class AuthResult {
  const AuthResult(this.token, this.principal);
  final String token;
  final Principal principal;

  Map<String, dynamic> toJson() => {'token': token, 'user': principal.toJson()};
}

class AuthRepository {
  AuthRepository(this.db);

  final Db db;

  static const int maxAttempts = 5;
  static const int lockoutMinutes = 5;
  static const int sessionHours = 12;
  static final Random _random = Random.secure();

  // Verifying against a throwaway hash when the email is unknown keeps the
  // response time similar, so timing does not reveal which emails exist.
  static final String _dummyHash = BCrypt.hashpw('drakkar-dummy', BCrypt.gensalt());

  /// Creates an organization and its owner, then signs the owner in.
  Future<AuthResult> signup({
    required String organization,
    required String name,
    required String email,
    required String password,
  }) async {
    final passwordHash = await _hashPassword(password);
    final result = await db.pool.runTx<AuthResult?>((tx) async {
      final existing = await tx.execute(
        Sql.named('SELECT 1 FROM users WHERE lower(email) = lower(@email)'),
        parameters: {'email': email},
      );
      if (existing.isNotEmpty) return null;

      final tenantRows = await tx.execute(
        Sql.named('INSERT INTO tenants (name) VALUES (@name) RETURNING CAST(id AS text)'),
        parameters: {'name': organization},
      );
      final tenantId = tenantRows.first[0]! as String;
      await Db.setTenant(tx, tenantId);

      final userRows = await tx.execute(
        Sql.named(
          'INSERT INTO users (tenant_id, email, password_hash, name, role) '
          "VALUES (CAST(@tenant AS uuid), @email, @hash, @name, 'owner') "
          'RETURNING CAST(id AS text)',
        ),
        parameters: {'tenant': tenantId, 'email': email, 'hash': passwordHash, 'name': name},
      );
      final userId = userRows.first[0]! as String;
      final token = await _createSession(tx, userId: userId, tenantId: tenantId);
      await writeAudit(tx,
          tenantId: tenantId, userId: userId, action: 'SIGNUP', entityType: 'tenant', entityId: tenantId);
      return AuthResult(
        token,
        Principal(
          userId: userId,
          tenantId: tenantId,
          tenantName: organization,
          role: 'owner',
          name: name,
          email: email,
        ),
      );
    });
    if (result == null) {
      // Demo trade-off: a real signup flow would email the address instead of
      // confirming that the account exists.
      throw const ApiException(409, 'email_taken', 'An account with that email already exists.');
    }
    return result;
  }

  /// Verifies credentials. Failed attempts are committed before the error is
  /// thrown, so the lockout counter survives the failed request.
  Future<AuthResult> login(String email, String password) async {
    final outcome = await db.pool.runTx<Object>((tx) async {
      final rows = await tx.execute(
        Sql.named(
          'SELECT CAST(u.id AS text), CAST(u.tenant_id AS text), u.password_hash, '
          'u.failed_attempts, u.locked_until, u.name, u.role, u.email, t.name '
          'FROM users u JOIN tenants t ON t.id = u.tenant_id '
          'WHERE lower(u.email) = lower(@email) FOR UPDATE OF u',
        ),
        parameters: {'email': email},
      );
      if (rows.isEmpty) {
        await _checkPassword(password, _dummyHash);
        return ApiException.badCredentials;
      }
      final row = rows.first;
      final userId = row[0]! as String;
      final tenantId = row[1]! as String;
      final lockedUntil = row[4] as DateTime?;
      await Db.setTenant(tx, tenantId);

      if (lockedUntil != null && lockedUntil.isAfter(DateTime.now().toUtc())) {
        return const ApiException(429, 'locked', 'Too many failed attempts. Try again in a few minutes.');
      }

      if (!await _checkPassword(password, row[2]! as String)) {
        final attempts = (row[3]! as int) + 1;
        if (attempts >= maxAttempts) {
          await tx.execute(
            Sql.named(
              'UPDATE users SET failed_attempts = 0, '
              'locked_until = now() + make_interval(mins => $lockoutMinutes) '
              'WHERE id = CAST(@id AS uuid)',
            ),
            parameters: {'id': userId},
          );
          await writeAudit(tx,
              tenantId: tenantId, userId: userId, action: 'LOCKED_OUT', entityType: 'user', entityId: userId);
        } else {
          await tx.execute(
            Sql.named('UPDATE users SET failed_attempts = failed_attempts + 1 WHERE id = CAST(@id AS uuid)'),
            parameters: {'id': userId},
          );
        }
        await writeAudit(tx,
            tenantId: tenantId, userId: userId, action: 'FAILED_LOGIN', entityType: 'user', entityId: userId);
        return ApiException.badCredentials;
      }

      await tx.execute(
        Sql.named('UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = CAST(@id AS uuid)'),
        parameters: {'id': userId},
      );
      final token = await _createSession(tx, userId: userId, tenantId: tenantId);
      await writeAudit(tx,
          tenantId: tenantId, userId: userId, action: 'LOGIN', entityType: 'user', entityId: userId);
      return AuthResult(
        token,
        Principal(
          userId: userId,
          tenantId: tenantId,
          tenantName: row[8]! as String,
          role: row[6]! as String,
          name: row[5]! as String,
          email: row[7]! as String,
        ),
      );
    });
    if (outcome is ApiException) throw outcome;
    return outcome as AuthResult;
  }

  /// Resolves a bearer token to its user, or null if missing/expired.
  Future<Principal?> authenticate(String token) async {
    if (token.isEmpty || token.length > 200) return null;
    final rows = await db.pool.execute(
      Sql.named(
        'SELECT CAST(u.id AS text), CAST(u.tenant_id AS text), u.role, u.name, u.email, t.name '
        'FROM sessions s '
        'JOIN users u ON u.id = s.user_id '
        'JOIN tenants t ON t.id = s.tenant_id '
        'WHERE s.token_hash = @hash AND s.expires_at > now()',
      ),
      parameters: {'hash': hashToken(token)},
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Principal(
      userId: r[0]! as String,
      tenantId: r[1]! as String,
      role: r[2]! as String,
      name: r[3]! as String,
      email: r[4]! as String,
      tenantName: r[5]! as String,
    );
  }

  Future<void> logout(String token) async {
    await db.pool.execute(
      Sql.named('DELETE FROM sessions WHERE token_hash = @hash'),
      parameters: {'hash': hashToken(token)},
    );
  }

  Future<String> _createSession(TxSession tx, {required String userId, required String tenantId}) async {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    await tx.execute(
      Sql.named(
        'INSERT INTO sessions (token_hash, user_id, tenant_id, expires_at) '
        'VALUES (@hash, CAST(@user AS uuid), CAST(@tenant AS uuid), '
        'now() + make_interval(hours => $sessionHours))',
      ),
      parameters: {'hash': hashToken(token), 'user': userId, 'tenant': tenantId},
    );
    return token;
  }

  /// Only the SHA-256 of a token is stored; a database leak exposes no
  /// usable session.
  static String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();
}

// bcrypt is deliberately slow and synchronous. Running it on a short-lived
// worker isolate keeps this pod's event loop free, so health probes and other
// requests are still answered while a hash is being computed, and one pod can
// use more than one CPU core.
//
// These are top-level, non-async functions on purpose: the closure handed to
// Isolate.run must capture only plain strings. A closure created inside an
// async method could also capture the open database transaction, which cannot
// be sent to another isolate.
Future<String> _hashPassword(String password) =>
    Isolate.run(() => BCrypt.hashpw(password, BCrypt.gensalt()));

Future<bool> _checkPassword(String password, String hash) =>
    Isolate.run(() => BCrypt.checkpw(password, hash));
