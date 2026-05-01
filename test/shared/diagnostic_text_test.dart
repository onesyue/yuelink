import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/diagnostic_text.dart';

void main() {
  group('decodeLogBytesLossy', () {
    test('decodes valid utf-8 verbatim', () {
      const sample = 'normal ASCII line\n中文一行\n';
      final out = decodeLogBytesLossy(utf8.encode(sample));
      expect(out, sample);
    });

    test('does not throw on invalid utf-8 — substitutes U+FFFD', () {
      // 0xC3 0x28 is an invalid utf-8 sequence (incomplete 2-byte start).
      // event.log can pick these up if a half-flushed line crosses a
      // multi-byte boundary during a crash. The bundle MUST keep going.
      final bytes = <int>[
        ...utf8.encode('start '),
        0xC3,
        0x28,
        ...utf8.encode(' end\n'),
      ];
      final out = decodeLogBytesLossy(bytes);
      expect(out.contains('start'), isTrue);
      expect(out.contains('end'), isTrue);
      expect(out.contains('�'), isTrue);
    });

    test('falls through to latin1 on pathological bytes', () {
      // Pure 0x80..0xFF — invalid utf-8 starts but valid latin1 chars.
      // utf8.decode(allowMalformed) handles these by returning U+FFFD,
      // so we end up with a non-empty string either way. Test the
      // contract: never throws, never empty.
      final bytes = List<int>.generate(20, (i) => 0x80 + i);
      final out = decodeLogBytesLossy(bytes);
      expect(out, isNotEmpty);
      expect(() => decodeLogBytesLossy(bytes), returnsNormally);
    });

    test('empty input returns empty string', () {
      expect(decodeLogBytesLossy(const []), '');
    });
  });

  group('lossyUtf8', () {
    test('passes String through unchanged', () {
      expect(lossyUtf8('hello 世界'), 'hello 世界');
    });

    test('decodes List<int> via the same ladder as decodeLogBytesLossy', () {
      final raw = utf8.encode('hello 世界');
      expect(lossyUtf8(raw), 'hello 世界');
    });

    test('returns "" on null', () {
      expect(lossyUtf8(null), '');
    });

    test('handles invalid bytes without throwing', () {
      final raw = <int>[
        ...utf8.encode('keep '),
        0xFF,
        0xFE,
        ...utf8.encode(' me'),
      ];
      final out = lossyUtf8(raw);
      expect(out.contains('keep'), isTrue);
      expect(out.contains('me'), isTrue);
    });
  });

  group('winQuoteArg', () {
    test('passes simple args through unchanged', () {
      expect(winQuoteArg('netsh'), 'netsh');
      expect(winQuoteArg('--no-interactive'), '--no-interactive');
    });

    test('quotes args containing spaces', () {
      expect(winQuoteArg('hello world'), '"hello world"');
    });

    test('escapes embedded double quotes', () {
      // PowerShell `-Command` scripts with embedded literals.
      expect(winQuoteArg('say "hi"'), r'"say \"hi\""');
    });

    test('quotes empty string as ""', () {
      expect(winQuoteArg(''), '""');
    });

    test('escapes backslashes when quoting', () {
      // C:\Program Files\YueLink — has space → quote → backslashes
      // would otherwise terminate the quoted segment in cmd parsing.
      expect(
        winQuoteArg(r'C:\Program Files\YueLink'),
        r'"C:\\Program Files\\YueLink"',
      );
    });
  });

  group('readLogTextLossy', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diag_text_test_');
    });

    tearDown(() async {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('reads a clean utf-8 log file', () async {
      final f = File('${tmp.path}/event.log');
      await f.writeAsString('[Auth] login_ok cid=abc\n中文事件\n');
      final out = await readLogTextLossy(f);
      expect(out.contains('[Auth] login_ok'), isTrue);
      expect(out.contains('中文事件'), isTrue);
    });

    test('does NOT throw on the cp936 byte regression we hit on 2026-05-01',
        () async {
      // Real-world reproduction: event.log on a zh-Windows machine
      // contained one stray 0xCD byte (likely a logged OS string that
      // bypassed utf8.encode). File.readAsString() raised
      // FormatException; the diagnostic bundle then printed
      // "<read failed: FileSystemException: Failed to decode data
      // using encoding 'utf-8'>" instead of the actual log.
      final f = File('${tmp.path}/event.log');
      final bytes = <int>[
        ...utf8.encode('[Auth] login_ok\n'),
        0xCD,
        0xBC,
        0xCA,
        0xB1,
        0x0A,
        ...utf8.encode('[Sync] ok\n'),
      ];
      await f.writeAsBytes(bytes);
      final out = await readLogTextLossy(f);
      expect(out.contains('[Auth] login_ok'), isTrue);
      expect(out.contains('[Sync] ok'), isTrue);
    });
  });
}
