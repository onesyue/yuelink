import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/log_export_sources.dart';

/// Lock the v1.0.22 P3-A contract: diagnostic export must include
/// rotated `core.log` sidecars in chronological order so users
/// reproducing a crash that happened mid-session don't lose context
/// to the Go-side log rotation.

void main() {
  group('expandRotatedLogSources', () {
    test('core.log expands to chronological [.2, .1, current]', () {
      expect(
        expandRotatedLogSources(['core.log']),
        ['core.log.2', 'core.log.1', 'core.log'],
      );
    });

    test('non-rotating sources pass through unchanged', () {
      expect(
        expandRotatedLogSources(['crash.log', 'event.log']),
        ['crash.log', 'event.log'],
      );
    });

    test('mixed list keeps order, expands core.log in place', () {
      // Insertion point of the core.log sidecars matters: they must
      // sit alongside the live core.log so the bundle reads as one
      // continuous timeline, not after every other source.
      expect(
        expandRotatedLogSources([
          'core.log',
          'crash.log',
          'event.log',
          'startup_report.json',
        ]),
        [
          'core.log.2',
          'core.log.1',
          'core.log',
          'crash.log',
          'event.log',
          'startup_report.json',
        ],
      );
    });

    test('coreLogBackups: 0 keeps only the live file', () {
      // Defensive: aligning with a Go-side change that disables
      // rotation entirely should produce a sane single-element list.
      expect(
        expandRotatedLogSources(['core.log'], coreLogBackups: 0),
        ['core.log'],
      );
    });

    test('coreLogBackups: 4 produces .4 → .3 → .2 → .1 → current', () {
      expect(
        expandRotatedLogSources(['core.log'], coreLogBackups: 4),
        ['core.log.4', 'core.log.3', 'core.log.2', 'core.log.1', 'core.log'],
      );
    });

    test('empty input → empty output', () {
      expect(expandRotatedLogSources(const []), isEmpty);
    });

    test(
      'multiple core.log entries each get their own sidecar block '
      '(degenerate but well-defined)',
      () {
        // Not expected in production, but the function should not
        // silently dedupe — its job is purely list expansion.
        expect(
          expandRotatedLogSources(['core.log', 'crash.log', 'core.log']),
          [
            'core.log.2',
            'core.log.1',
            'core.log',
            'crash.log',
            'core.log.2',
            'core.log.1',
            'core.log',
          ],
        );
      },
    );
  });
}
