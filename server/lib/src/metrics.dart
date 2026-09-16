// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

/// Minimal in-process Prometheus metrics (per pod). Enough to show request
/// rate, error rate and latency in Grafana without extra dependencies.
class Metrics {
  final Map<String, int> _requests = {};
  double _latencySecondsSum = 0;
  int _latencyCount = 0;
  final DateTime _startedAt = DateTime.now();

  static const List<double> _buckets = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5];
  final List<int> _bucketCounts = List<int>.filled(_buckets.length, 0);

  void record(String method, int status, Duration elapsed) {
    final key = '$method|$status';
    _requests[key] = (_requests[key] ?? 0) + 1;
    final seconds = elapsed.inMicroseconds / 1e6;
    _latencySecondsSum += seconds;
    _latencyCount++;
    for (var i = 0; i < _buckets.length; i++) {
      if (seconds <= _buckets[i]) _bucketCounts[i]++;
    }
  }

  String render() {
    final b = StringBuffer()
      ..writeln('# HELP drakkar_http_requests_total HTTP requests handled by this pod.')
      ..writeln('# TYPE drakkar_http_requests_total counter');
    final keys = _requests.keys.toList()..sort();
    for (final key in keys) {
      final parts = key.split('|');
      b.writeln('drakkar_http_requests_total{method="${parts[0]}",code="${parts[1]}"} ${_requests[key]}');
    }
    b
      ..writeln('# HELP drakkar_http_request_duration_seconds Request latency.')
      ..writeln('# TYPE drakkar_http_request_duration_seconds histogram');
    for (var i = 0; i < _buckets.length; i++) {
      b.writeln('drakkar_http_request_duration_seconds_bucket{le="${_buckets[i]}"} ${_bucketCounts[i]}');
    }
    b
      ..writeln('drakkar_http_request_duration_seconds_bucket{le="+Inf"} $_latencyCount')
      ..writeln('drakkar_http_request_duration_seconds_sum $_latencySecondsSum')
      ..writeln('drakkar_http_request_duration_seconds_count $_latencyCount')
      ..writeln('# HELP drakkar_uptime_seconds Seconds since this pod started.')
      ..writeln('# TYPE drakkar_uptime_seconds gauge')
      ..writeln('drakkar_uptime_seconds ${DateTime.now().difference(_startedAt).inSeconds}');
    return b.toString();
  }
}
