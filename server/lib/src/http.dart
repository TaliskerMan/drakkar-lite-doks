// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'dart:convert';

import 'package:shelf/shelf.dart';

const Map<String, String> jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// An error that maps directly to an HTTP response.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  static const unauthorized = ApiException(401, 'unauthorized', 'Sign in required.');
  static const forbidden = ApiException(403, 'forbidden', 'Your role does not allow this.');
  static const notFound = ApiException(404, 'not_found', 'Not found.');
  static const badCredentials =
      ApiException(401, 'bad_credentials', 'Email or password is incorrect.');

  factory ApiException.badRequest(String message) =>
      ApiException(400, 'bad_request', message);

  final int status;
  final String code;
  final String message;

  Response toResponse() => jsonResponse(
        {
          'error': {'code': code, 'message': message},
        },
        status: status,
      );

  @override
  String toString() => 'ApiException($status, $code)';
}

Response jsonResponse(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: jsonHeaders);

const int _maxBodyBytes = 1024 * 1024;

/// Reads a JSON object body, rejecting oversized or malformed input.
Future<Map<String, dynamic>> readJson(Request request) async {
  final length = request.contentLength;
  if (length != null && length > _maxBodyBytes) {
    throw const ApiException(413, 'too_large', 'Request body is too large.');
  }
  final text = await request.readAsString();
  if (text.length > _maxBodyBytes) {
    throw const ApiException(413, 'too_large', 'Request body is too large.');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw ApiException.badRequest('Body must be valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ApiException.badRequest('Body must be a JSON object.');
  }
  return decoded;
}

/// Reads a required, trimmed string field.
String requireString(Map<String, dynamic> body, String field, {int maxLength = 200}) {
  final value = body[field];
  if (value is! String || value.trim().isEmpty) {
    throw ApiException.badRequest('$field is required.');
  }
  final trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw ApiException.badRequest('$field must be $maxLength characters or fewer.');
  }
  return trimmed;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Path IDs must be UUIDs; anything else is simply "not found".
String requireUuid(String value) {
  if (!_uuid.hasMatch(value)) throw ApiException.notFound;
  return value.toLowerCase();
}

/// Escapes `%`, `_` and `\` so user search text is matched literally in ILIKE.
String likePattern(String query) {
  final escaped = query
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

/// The authenticated caller, attached to the request context by middleware.
class Principal {
  const Principal({
    required this.userId,
    required this.tenantId,
    required this.tenantName,
    required this.role,
    required this.name,
    required this.email,
  });

  final String userId;
  final String tenantId;
  final String tenantName;
  final String role;
  final String name;
  final String email;

  bool get canWrite => role == 'owner' || role == 'admin';

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'tenantId': tenantId,
        'tenantName': tenantName,
        'role': role,
        'name': name,
        'email': email,
      };
}

Principal principalOf(Request request) {
  final principal = request.context['principal'];
  if (principal is! Principal) throw ApiException.unauthorized;
  return principal;
}

Principal requireWriter(Request request) {
  final principal = principalOf(request);
  if (!principal.canWrite) throw ApiException.forbidden;
  return principal;
}
