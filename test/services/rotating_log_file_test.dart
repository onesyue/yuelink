import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/rotating_log_file.dart';

/// v1.0.22 P3-B: lock the size-based rotation contract that
/// [appendWithRotation] applies to crash.log (and any future caller
/// that opts into the same shape).

void main() {
  late Directory tempDir;
  late File live;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yuelink_rotating_log_');
    live = File('${tempDir.path}/test.log');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('first append creates the file', () async {
    await appendWithRotation(live, 'hello\n');
    expect(await live.readAsString(), 'hello\n');
  });

  test('appends below cap stay in the live file', () async {
    await appendWithRotation(live, 'a' * 100, maxBytes: 1000);
    await appendWithRotation(live, 'b' * 100, maxBytes: 1000);
    final content = await live.readAsString();
    expect(content.length, 200);
    expect(File('${live.path}.1').existsSync(), isFalse);
  });

  test(
    'append that would cross cap rotates current to .1 first, then writes',
    () async {
      // Pre-fill close to cap so the next append would push over.
      await live.writeAsString('A' * 800);
      await appendWithRotation(live, 'B' * 300, maxBytes: 1000);

      // .1 should now hold the original 800 bytes; live should hold
      // just the new 300-byte append.
      expect(await File('${live.path}.1').readAsString(), 'A' * 800);
      expect(await live.readAsString(), 'B' * 300);
    },
  );

  test('only one .N sidecar is kept when backups: 1 (default)', () async {
    await live.writeAsString('A' * 800);
    await appendWithRotation(live, 'B' * 300, maxBytes: 1000);
    // Live now holds 'B'*300, .1 holds 'A'*800.

    await live.writeAsString('A' * 800, mode: FileMode.append);
    // Live now ~1100 bytes — next append should rotate again.
    await appendWithRotation(live, 'C' * 300, maxBytes: 1000);

    // .1 now holds the previously-live content; the original .1
    // ('A'*800) rolled off because backups=1.
    expect(File('${live.path}.2').existsSync(), isFalse,
        reason: 'backups=1 must not produce a .2 sidecar');
    expect(await live.readAsString(), 'C' * 300);
    final firstBackup = await File('${live.path}.1').readAsString();
    expect(firstBackup.contains('B' * 300), isTrue,
        reason: '.1 contains the most recent rotated generation');
  });

  test('backups: 2 promotes .1 → .2 then live → .1', () async {
    // Round 1: live ('A'*800) → .1; new append 'B'*300 → live.
    await live.writeAsString('A' * 800);
    await appendWithRotation(live, 'B' * 300, maxBytes: 1000, backups: 2);

    // Round 2: append more so we trigger another rotation.
    await live.writeAsString('B' * 800, mode: FileMode.append);
    await appendWithRotation(live, 'C' * 300, maxBytes: 1000, backups: 2);

    // Expectations:
    //   live = 'C'*300
    //   .1   = previous live ('B'*300 + 'B'*800 = 'B'*1100)
    //   .2   = original 'A'*800 (promoted from .1)
    expect(await live.readAsString(), 'C' * 300);
    expect(await File('${live.path}.2').readAsString(), 'A' * 800);
    expect(File('${live.path}.3').existsSync(), isFalse,
        reason: 'backups=2 must cap at .2');
  });

  test('backups: 0 hard-discards live content on rotation', () async {
    await live.writeAsString('A' * 800);
    await appendWithRotation(live, 'B' * 300, maxBytes: 1000, backups: 0);

    expect(await live.readAsString(), 'B' * 300);
    expect(File('${live.path}.1').existsSync(), isFalse,
        reason: 'backups=0 deletes the live file outright, no sidecar');
  });

  test('rotation triggers on size + entry sum, not just current size',
      () async {
    // Live is 100 bytes — under 1000 cap on its own. But appending
    // 950 bytes would push the post-write size to 1050. Helper must
    // rotate BEFORE the append so the post-write live file stays
    // bounded.
    await live.writeAsString('A' * 100);
    await appendWithRotation(live, 'B' * 950, maxBytes: 1000);

    expect(await File('${live.path}.1').readAsString(), 'A' * 100);
    expect(await live.readAsString(), 'B' * 950);
  });

  test('append after a missing parent dir is a fail-soft no-op (no throw)',
      () async {
    // path inside a directory that doesn't exist anymore — emulates
    // an Android getExternalStorageDirectory disappearing on user
    // unmount. Helper must not propagate the IO error (callers are
    // typically already in an exception handler).
    final orphan =
        File('${tempDir.path}/does/not/exist/orphan.log');
    await expectLater(
      appendWithRotation(orphan, 'never gets here'),
      completes,
    );
    expect(orphan.existsSync(), isFalse);
  });
}
