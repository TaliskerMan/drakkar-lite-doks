// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.
//
// Replaces Valhalla's direct DatabaseService calls with HTTP calls to the API.

import 'dart:convert';

import 'package:drakkar_core/drakkar_core.dart';
import 'package:http/http.dart' as http;

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}

/// The signed-in user, as returned by /v1/auth/signup and /v1/auth/login.
class Session {
  Session({
    required this.token,
    required this.userId,
    required this.tenantName,
    required this.role,
    required this.name,
    required this.email,
  });

  factory Session.fromJson(String token, Map<String, dynamic> user) => Session(
        token: token,
        userId: user['userId'] as String,
        tenantName: user['tenantName'] as String,
        role: user['role'] as String,
        name: user['name'] as String,
        email: user['email'] as String,
      );

  final String token;
  final String userId;
  final String tenantName;
  final String role;
  final String name;
  final String email;

  bool get canWrite => role == 'owner' || role == 'admin';
}

class AuditEntry {
  AuditEntry({required this.action, required this.createdAt, this.userName, this.entityType});

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        action: json['action'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        userName: json['userName'] as String?,
        entityType: json['entityType'] as String?,
      );

  final String action;
  final DateTime createdAt;
  final String? userName;
  final String? entityType;
}

class ApiClient {
  ApiClient({http.Client? httpClient, Uri? baseUri})
      : _http = httpClient ?? http.Client(),
        _base = baseUri ?? _defaultBase();

  /// In the cluster the app is served from the same origin as the API, so
  /// relative URLs work. For `flutter run -d chrome`, pass
  /// `--dart-define=API_BASE=http://localhost:8080`.
  static Uri _defaultBase() {
    const configured = String.fromEnvironment('API_BASE');
    return configured.isNotEmpty ? Uri.parse(configured) : Uri.base;
  }

  final http.Client _http;
  final Uri _base;
  String? token;

  /// Called with the pod name from the `x-served-by` response header.
  void Function(String pod)? onServedBy;

  Future<Session> signup({
    required String organization,
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await _send('POST', '/v1/auth/signup', body: {
      'organization': organization,
      'name': name,
      'email': email,
      'password': password,
    });
    return _startSession(json! as Map<String, dynamic>);
  }

  Future<Session> login(String email, String password) async {
    final json = await _send('POST', '/v1/auth/login', body: {
      'email': email,
      'password': password,
    });
    return _startSession(json! as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _send('POST', '/v1/auth/logout');
    } finally {
      token = null;
    }
  }

  Future<List<Contact>> contacts({String query = ''}) async {
    final json = await _send(
      'GET',
      '/v1/contacts',
      query: query.isEmpty ? null : {'q': query},
    );
    final items = (json! as Map<String, dynamic>)['items'] as List<dynamic>;
    return [for (final item in items) Contact.fromJson(item as Map<String, dynamic>)];
  }

  Future<Contact> createContact(Contact contact) async {
    final json = await _send('POST', '/v1/contacts', body: contact.toJson());
    return Contact.fromJson(json! as Map<String, dynamic>);
  }

  Future<void> deleteContact(String id) async {
    await _send('DELETE', '/v1/contacts/$id');
  }

  Future<List<AuditEntry>> auditLog() async {
    final json = await _send('GET', '/v1/audit-logs');
    final items = (json! as Map<String, dynamic>)['items'] as List<dynamic>;
    return [for (final item in items) AuditEntry.fromJson(item as Map<String, dynamic>)];
  }

  Session _startSession(Map<String, dynamic> json) {
    final newToken = json['token'] as String;
    token = newToken;
    return Session.fromJson(newToken, json['user'] as Map<String, dynamic>);
  }

  Uri _uri(String path, Map<String, String>? query) {
    final resolved = _base.resolve(path);
    return query == null ? resolved : resolved.replace(queryParameters: query);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final response = await http.Response.fromStream(await _http.send(request));

    final pod = response.headers['x-served-by'];
    if (pod != null) onServedBy?.call(pod);

    if (response.statusCode >= 400) {
      var message = 'Request failed (${response.statusCode}).';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final error = decoded['error'];
          if (error is Map<String, dynamic> && error['message'] is String) {
            message = error['message'] as String;
          }
        }
      } on FormatException {
        // Non-JSON error body (e.g. from a proxy); keep the generic message.
      }
      throw ApiError(response.statusCode, message);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }
}
