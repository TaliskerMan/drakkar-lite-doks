// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'dart:io';

import 'package:postgres/postgres.dart';

/// Runtime configuration, read from environment variables (12-factor style,
/// so Kubernetes injects it from a ConfigMap/Secret).
class Config {
  Config({
    required this.port,
    required this.endpoint,
    required this.sslMode,
    this.corsOrigin,
  });

  /// Reads the first non-empty variable in [urlVariables] as a
  /// `postgresql://user:password@host:port/database?sslmode=require` URL.
  factory Config.fromEnvironment({
    List<String> urlVariables = const ['DATABASE_URL'],
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    String? raw;
    for (final name in urlVariables) {
      final value = env[name];
      if (value != null && value.isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null) {
      throw StateError('Set one of: ${urlVariables.join(', ')}');
    }
    final parsed = parseDatabaseUrl(raw);
    return Config(
      port: int.tryParse(env['PORT'] ?? '') ?? 8080,
      endpoint: parsed.endpoint,
      sslMode: parsed.sslMode,
      corsOrigin: env['CORS_ORIGIN'],
    );
  }

  final int port;
  final Endpoint endpoint;
  final SslMode sslMode;

  /// Only for local development when the web client runs on another origin.
  final String? corsOrigin;
}

/// Parses a Postgres URL into an [Endpoint] and [SslMode].
({Endpoint endpoint, SslMode sslMode}) parseDatabaseUrl(String url) {
  final uri = Uri.parse(url);
  if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
    throw FormatException('Database URL must start with postgresql://');
  }
  final info = uri.userInfo;
  final colon = info.indexOf(':');
  final user = colon < 0 ? info : info.substring(0, colon);
  final password = colon < 0 ? null : info.substring(colon + 1);
  final sslParam = uri.queryParameters['sslmode'] ?? 'require';
  final SslMode sslMode;
  switch (sslParam) {
    case 'disable':
      sslMode = SslMode.disable;
    case 'verify-full':
      sslMode = SslMode.verifyFull;
    default:
      // DigitalOcean Managed PostgreSQL requires TLS; `require` encrypts but
      // does not verify the CA. Use verify-full once the DO CA cert is trusted.
      sslMode = SslMode.require;
  }
  return (
    endpoint: Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
      username: Uri.decodeComponent(user),
      password: password == null ? null : Uri.decodeComponent(password),
    ),
    sslMode: sslMode,
  );
}
