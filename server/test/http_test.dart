import 'package:drakkar_api/drakkar_api.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  group('parseDatabaseUrl', () {
    test('parses a DigitalOcean-style URL', () {
      final parsed = parseDatabaseUrl(
        'postgresql://drakkar_app:p%40ss%3Aword@private-db.example.com:25060/drakkar?sslmode=require',
      );
      expect(parsed.endpoint.host, 'private-db.example.com');
      expect(parsed.endpoint.port, 25060);
      expect(parsed.endpoint.database, 'drakkar');
      expect(parsed.endpoint.username, 'drakkar_app');
      expect(parsed.endpoint.password, 'p@ss:word');
      expect(parsed.sslMode, SslMode.require);
    });

    test('supports sslmode=disable for local compose', () {
      final parsed = parseDatabaseUrl('postgres://u:p@db/drakkar?sslmode=disable');
      expect(parsed.endpoint.port, 5432);
      expect(parsed.sslMode, SslMode.disable);
    });

    test('rejects other schemes', () {
      expect(() => parseDatabaseUrl('mysql://u:p@db/x'), throwsFormatException);
    });
  });

  test('Config reads the first variable that is set', () {
    final config = Config.fromEnvironment(
      urlVariables: const ['MIGRATOR_DATABASE_URL', 'DATABASE_URL'],
      environment: const {
        'DATABASE_URL': 'postgresql://app:x@db/drakkar',
        'PORT': '9090',
      },
    );
    expect(config.endpoint.username, 'app');
    expect(config.port, 9090);
  });

  test('likePattern escapes wildcards', () {
    expect(likePattern('50%_off'), r'%50\%\_off%');
    expect(likePattern(r'a\b'), r'%a\\b%');
  });

  group('requireUuid', () {
    test('accepts and lower-cases UUIDs', () {
      expect(requireUuid('7D1F0C1E-7C4C-4A8E-9A55-2B1F7C1F0A11'),
          '7d1f0c1e-7c4c-4a8e-9a55-2b1f7c1f0a11');
    });

    test('treats anything else as not found', () {
      expect(() => requireUuid('1'), throwsA(isA<ApiException>()));
      expect(() => requireUuid("1' OR '1'='1"), throwsA(isA<ApiException>()));
    });
  });

  test('Metrics renders Prometheus text', () {
    final metrics = Metrics()..record('GET', 200, const Duration(milliseconds: 12));
    final text = metrics.render();
    expect(text, contains('drakkar_http_requests_total{method="GET",code="200"} 1'));
    expect(text, contains('drakkar_http_request_duration_seconds_count 1'));
  });
}
