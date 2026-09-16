// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';

import 'auth_repository.dart';
import 'http.dart';
import 'metrics.dart';

/// Pod name (Kubernetes sets HOSTNAME to it). Returned as `x-served-by` so the
/// web client can show which replica answered.
final String servedBy = Platform.environment['HOSTNAME'] ?? Platform.localHostname;

const Set<String> _quietPaths = {'healthz', 'readyz', 'metrics'};
const Set<String> _publicApiPaths = {'v1/auth/signup', 'v1/auth/login'};
final Random _random = Random();

/// Outermost middleware: request id, error mapping, metrics, JSON access log.
Middleware observe(Metrics metrics) {
  return (Handler inner) {
    return (Request request) async {
      final started = DateTime.now();
      final requestId = request.headers['x-request-id'] ??
          List.generate(8, (_) => _random.nextInt(16).toRadixString(16)).join();
      Response response;
      try {
        response = await inner(request.change(context: {'requestId': requestId}));
      } on ApiException catch (e) {
        response = e.toResponse();
      } catch (error, stack) {
        stderr.writeln(jsonEncode({
          'level': 'error',
          'requestId': requestId,
          'error': error.toString(),
          'stack': stack.toString().split('\n').take(8).join(' | '),
        }));
        response = const ApiException(500, 'internal', 'Something went wrong.').toResponse();
      }
      final elapsed = DateTime.now().difference(started);
      metrics.record(request.method, response.statusCode, elapsed);
      if (!_quietPaths.contains(request.url.path)) {
        stdout.writeln(jsonEncode({
          'level': 'info',
          'ts': started.toUtc().toIso8601String(),
          'requestId': requestId,
          'method': request.method,
          'path': '/${request.url.path}',
          'status': response.statusCode,
          'ms': elapsed.inMilliseconds,
          'pod': servedBy,
        }));
      }
      return response.change(headers: {
        'x-request-id': requestId,
        'x-served-by': servedBy,
        'x-content-type-options': 'nosniff',
        'cache-control': 'no-store',
      });
    };
  };
}

/// Resolves `Authorization: Bearer <token>` for /v1 routes (except signup and
/// login) and stores the caller in the request context.
Middleware authenticate(AuthRepository auth) {
  return (Handler inner) {
    return (Request request) async {
      final path = request.url.path;
      if (!path.startsWith('v1/') || _publicApiPaths.contains(path)) {
        return inner(request);
      }
      final token = bearerToken(request);
      if (token == null) throw ApiException.unauthorized;
      final principal = await auth.authenticate(token);
      if (principal == null) throw ApiException.unauthorized;
      return inner(request.change(context: {'principal': principal, 'token': token}));
    };
  };
}

String? bearerToken(Request request) {
  final header = request.headers['authorization'];
  if (header == null || !header.startsWith('Bearer ')) return null;
  final token = header.substring(7).trim();
  return token.isEmpty ? null : token;
}

/// Local development only: allow a web client on another origin
/// (e.g. `flutter run -d chrome`). In the cluster the web app is same-origin.
Middleware cors(String? allowedOrigin) {
  return (Handler inner) {
    if (allowedOrigin == null || allowedOrigin.isEmpty) return inner;
    const allowHeaders = 'authorization, content-type, x-request-id';
    final corsHeaders = {
      'access-control-allow-origin': allowedOrigin,
      'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
      'access-control-allow-headers': allowHeaders,
      'access-control-expose-headers': 'x-served-by, x-request-id',
    };
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response(204, headers: corsHeaders);
      }
      final response = await inner(request);
      return response.change(headers: corsHeaders);
    };
  };
}
