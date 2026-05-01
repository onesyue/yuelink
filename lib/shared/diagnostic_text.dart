import 'dart:convert';
import 'dart:io';

/// Lossy log-text decoder for the diagnostic bundle.
///
/// Default `File.readAsString()` uses strict UTF-8 and throws on the
/// first invalid byte. event.log is mostly Dart-side writes (always
/// UTF-8) but can pick up cp936 bytes if a future caller logs a
/// localized OS string without re-encoding, or if a half-flushed line
/// crosses a multi-byte boundary during a crash. The diagnostic bundle
/// is best-effort triage — drop the substitution character on bad
/// bytes, never refuse the file.
///
/// Decoding ladder:
///   1. Strict UTF-8 (fast path; works for every Dart-side log).
///   2. UTF-8 with `allowMalformed: true` so invalid sequences become
///      U+FFFD instead of throwing.
///   3. latin1 with `allowInvalid: true` as a last resort so even
///      pathological binary can be inspected.
Future<String> readLogTextLossy(File f) async {
  final bytes = await f.readAsBytes();
  return decodeLogBytesLossy(bytes);
}

/// Pure helper extracted for testability — same decoding ladder as
/// [readLogTextLossy] but operates on already-loaded bytes.
String decodeLogBytesLossy(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
}

/// Decode `Process.run` stdout/stderr with the same lossy contract.
/// Process.run returns `dynamic` for stdout/stderr (`List<int>` when
/// encoding is null, `String` otherwise) so accept both.
String lossyUtf8(dynamic raw) {
  if (raw is String) return raw;
  if (raw is List<int>) return decodeLogBytesLossy(raw);
  return raw?.toString() ?? '';
}

/// Spawn a diagnostic command, forcing UTF-8 console output on Windows.
///
/// Plain `Process.run('netsh', ...)` on a localized Windows (zh-CN,
/// ja-JP, …) returns bytes in the active console codepage
/// (cp936 / cp932 / …). Dart decodes those as `systemEncoding`, which
/// for the FFI runtime here is UTF-8 — so multi-byte glyphs come out
/// as `鐘舵€?` mojibake in the exported diagnostic bundle.
///
/// Wrap each command in `cmd /c chcp 65001 >nul && <exe> <args>`. The
/// active codepage is process-scoped, so per-command wrapping is
/// enough; it does not affect any other process. We also request raw
/// bytes via `stdoutEncoding: null` and decode with [lossyUtf8] so the
/// codepage switch is the only encoding contract we rely on.
Future<ProcessResult> runDiagnosticCommand(
  String exe,
  List<String> args, {
  ProcessRunner? runner,
}) {
  final r = runner ?? Process.run;
  if (Platform.isWindows) {
    final body = ([exe, ...args]).map(winQuoteArg).join(' ');
    return r(
      'cmd',
      ['/c', 'chcp 65001 >nul && $body'],
      stdoutEncoding: null,
      stderrEncoding: null,
    );
  }
  return r(
    exe,
    args,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
}

/// Injection point for tests — accepts the same shape as `Process.run`.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
});

/// Minimal Windows-cmd argument quoting. Diagnostic commands are
/// hardcoded by callers; this only has to handle the actual call sites
/// (paths with spaces in user profile, PowerShell `-Command` scripts
/// with embedded quotes).
String winQuoteArg(String arg) {
  if (arg.isEmpty) return '""';
  if (!arg.contains(RegExp(r'[\s"]'))) return arg;
  return '"${arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
