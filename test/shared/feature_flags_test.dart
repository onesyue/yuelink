import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/feature_flags.dart';

void main() {
  group('FeatureFlags', () {
    test('builds the server flags URI with a non-empty client_id query', () {
      final uri = FeatureFlags.flagsUriForClientId('client 123');

      expect(uri.scheme, 'https');
      expect(uri.path, '/api/client/telemetry/flags');
      expect(uri.queryParameters['client_id'], 'client 123');
      expect(uri.toString(), contains('client_id=client+123'));
    });
  });
}
