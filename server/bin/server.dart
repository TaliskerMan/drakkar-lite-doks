// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.
//
// One binary, two commands:
//   server serve    — run the HTTP API (Kubernetes Deployment)
//   server migrate  — apply database migrations (Kubernetes Job)

import 'dart:convert';
import 'dart:io';

import 'package:drakkar_api/drakkar_api.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'serve' : args.first;
  switch (command) {
    case 'serve':
      await _serve();
    case 'migrate':
      await _migrate();
    default:
      stderr.writeln('usage: server [serve|migrate]');
      exitCode = 64;
  }
}

Future<void> _migrate() async {
  final config = Config.fromEnvironment(
    urlVariables: const ['MIGRATOR_DATABASE_URL', 'DATABASE_URL'],
  );
  final db = Db.open(config, maxConnections: 1);
  try {
    await runMigrations(db.pool);
  } finally {
    await db.close();
  }
}

Future<void> _serve() async {
  final config = Config.fromEnvironment();
  final maxConnections = int.tryParse(Platform.environment['DB_POOL_SIZE'] ?? '') ?? 3;
  final db = Db.open(config, maxConnections: maxConnections);
  final handler = buildHandler(db: db, metrics: Metrics(), corsOrigin: config.corsOrigin);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, config.port);
  server.autoCompress = true;
  _log('listening', {'port': config.port, 'dbPool': maxConnections});

  // Kubernetes sends SIGTERM before killing a pod. Stop accepting new
  // connections, let in-flight requests finish, then close the pool.
  var stopping = false;
  Future<void> shutdown(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    _log('shutting down', {'signal': signal.toString()});
    await server.close();
    await db.close();
    _log('stopped', const {});
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}

void _log(String msg, Map<String, Object?> fields) {
  stdout.writeln(jsonEncode({
    'level': 'info',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'msg': msg,
    ...fields,
  }));
}
