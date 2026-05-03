// ignore_for_file: avoid_print
// YueLink build orchestrator
// Compiles the Go (mihomo) core into platform-native shared/static libraries.
//
// Usage:
//   dart setup.dart <command> [options]
//
// Commands:
//   build   Build the Go core for a specific platform
//   install Copy built libraries to Flutter platform directories
//   clean   Remove all compiled core artifacts
//
// Build options:
//   --platform, -p   Target platform: android, ios, macos, windows
//   --arch, -a       Target architecture: arm64, amd64, arm (default: all)
//   --debug          Build with debug symbols (default: release)
//
// Examples:
//   dart setup.dart build -p android               # Build all Android arches
//   dart setup.dart build -p android -a arm64       # Build Android arm64 only
//   dart setup.dart build -p ios                    # Build iOS (arm64 only)
//   dart setup.dart build -p macos                  # Build macOS universal
//   dart setup.dart build -p windows -a amd64       # Build Windows x64
//   dart setup.dart install -p macos                # Copy + lipo universal
//   dart setup.dart clean                           # Remove all artifacts

import 'dart:io';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String corePath = 'core';
const String outputDir = 'core/build';
const String servicePath = 'service';
const String serviceOutputDir = 'service/build';

// Service protocol version now lives in `service/protocol_version.txt` —
// Go embeds it via `//go:embed`, Dart reads it as a Flutter asset. Neither
// setup.dart nor anything else needs to care about the value.

/// Android API level for the NDK toolchain.
const String androidApiLevel = '21';

/// Map of (platform, arch) → output file name.
const Map<String, Map<String, String>> outputNames = {
  'android': {
    'arm64': 'android-arm64/libclash.so',
    'arm': 'android-arm/libclash.so',
    'amd64': 'android-x86_64/libclash.so',
  },
  'ios': {
    'arm64': 'ios-arm64/libclash.a',
  },
  'macos': {
    'arm64': 'macos-arm64/libclash.dylib',
    'amd64': 'macos-amd64/libclash.dylib',
  },
  'windows': {
    'amd64': 'windows-amd64/libclash.dll',
    'arm64': 'windows-arm64/libclash.dll',
  },
  'linux': {
    'amd64': 'linux-amd64/libclash.so',
    'arm64': 'linux-arm64/libclash.so',
  },
};

const Map<String, Map<String, String>> serviceHelperOutputNames = {
  'macos': {
    'arm64': 'macos-arm64/yuelink-service-helper',
    'amd64': 'macos-amd64/yuelink-service-helper',
  },
  'windows': {
    'amd64': 'windows-amd64/yuelink-service-helper.exe',
    'arm64': 'windows-arm64/yuelink-service-helper.exe',
  },
  'linux': {
    'amd64': 'linux-amd64/yuelink-service-helper',
    'arm64': 'linux-arm64/yuelink-service-helper',
  },
};

const Map<String, Map<String, String>> serviceMihomoOutputNames = {
  'macos': {
    'arm64': 'macos-arm64/yuelink-mihomo',
    'amd64': 'macos-amd64/yuelink-mihomo',
  },
  'windows': {
    'amd64': 'windows-amd64/yuelink-mihomo.exe',
    'arm64': 'windows-arm64/yuelink-mihomo.exe',
  },
  'linux': {
    'amd64': 'linux-amd64/yuelink-mihomo',
    'arm64': 'linux-arm64/yuelink-mihomo',
  },
};

/// Android NDK triple for each architecture.
const Map<String, String> androidNdkTriple = {
  'arm64': 'aarch64-linux-android',
  'arm': 'armv7a-linux-androideabi',
  'amd64': 'x86_64-linux-android',
};

/// Go GOARCH values.
const Map<String, String> goArchMap = {
  'arm64': 'arm64',
  'arm': 'arm',
  'amd64': 'amd64',
  'x86_64': 'amd64',
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns the host architecture mapped to our canonical names.
String get hostArch {
  final result = Process.runSync('uname', ['-m']);
  final raw = (result.stdout as String).trim();
  if (raw == 'x86_64') return 'amd64';
  if (raw == 'aarch64' || raw == 'arm64') return 'arm64';
  return raw;
}

/// Returns the host OS.
String get hostOS {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  throw Exception('Unsupported host OS');
}

/// Resolve the Android NDK path.
String resolveAndroidNdk() {
  // 1. ANDROID_NDK env var
  final envNdk = Platform.environment['ANDROID_NDK'];
  if (envNdk != null && Directory(envNdk).existsSync()) return envNdk;

  // 2. ANDROID_NDK_HOME env var
  final envNdkHome = Platform.environment['ANDROID_NDK_HOME'];
  if (envNdkHome != null && Directory(envNdkHome).existsSync()) {
    return envNdkHome;
  }

  // 3. Derive from ANDROID_HOME / ANDROID_SDK_ROOT
  final sdkRoot = Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  if (sdkRoot != null) {
    final ndkDir = Directory('$sdkRoot/ndk');
    if (ndkDir.existsSync()) {
      final versions = ndkDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split('/').last)
          .where((name) => !name.startsWith('.'))
          .toList()
        ..sort();
      if (versions.isNotEmpty) {
        return '${ndkDir.path}/${versions.last}';
      }
    }
  }

  throw Exception(
    'Cannot find Android NDK. Set ANDROID_NDK, ANDROID_NDK_HOME, or ANDROID_HOME env var.',
  );
}

/// Find the NDK C compiler for the given arch.
String resolveAndroidCC(String ndkPath, String arch) {
  final triple = androidNdkTriple[arch]!;
  final hostTag = Platform.isMacOS ? 'darwin-x86_64' : 'linux-x86_64';
  final prebuilt = '$ndkPath/toolchains/llvm/prebuilt/$hostTag/bin';

  // clang binary: <triple><api>-clang
  final clang = '$prebuilt/$triple$androidApiLevel-clang';
  if (File(clang).existsSync()) return clang;

  // Try without API level suffix (newer NDK)
  final clangNoApi = '$prebuilt/$triple-clang';
  if (File(clangNoApi).existsSync()) return clangNoApi;

  throw Exception('Cannot find Android clang at: $clang');
}

/// Run a command, printing it and streaming output. Throws on failure.
Future<void> run(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
}) async {
  final envDisplay =
      environment?.entries.map((e) => '${e.key}=${e.value}').join(' ') ?? '';
  print(
      '\n\$ ${envDisplay.isNotEmpty ? "$envDisplay " : ""}$executable ${args.join(" ")}');

  final process = await Process.start(
    executable,
    args,
    environment: environment,
    workingDirectory: workingDirectory,
    includeParentEnvironment: true,
  );

  process.stdout.listen((data) => stdout.add(data));
  process.stderr.listen((data) => stderr.add(data));

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception('Command failed with exit code $exitCode');
  }
}

// ---------------------------------------------------------------------------
// Build logic
// ---------------------------------------------------------------------------

Future<void> buildCore({
  required String platform,
  required String arch,
  required bool debug,
}) async {
  final goArch = goArchMap[arch] ?? arch;
  final platformArchNames = outputNames[platform];
  if (platformArchNames == null) {
    throw Exception(
        'Unsupported platform: $platform. Supported: android, ios, macos, windows');
  }
  final outName = platformArchNames[arch];
  if (outName == null) {
    throw Exception('Unsupported arch "$arch" for platform "$platform"');
  }

  final outPath = '$outputDir/$outName';
  final outDir = File(outPath).parent;
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // Common environment
  final env = <String, String>{
    'CGO_ENABLED': '1',
  };

  // Common ldflags
  final ldflags = <String>[
    if (!debug) '-s',
    if (!debug) '-w',
    '-X "github.com/metacubex/mihomo/constant.Version=yuelink"',
  ];

  String buildMode;
  List<String> extraArgs = [];

  switch (platform) {
    // -----------------------------------------------------------------
    // Android
    // -----------------------------------------------------------------
    case 'android':
      final ndkPath = resolveAndroidNdk();
      final cc = resolveAndroidCC(ndkPath, arch);
      env['GOOS'] = 'android';
      env['GOARCH'] = goArch;
      env['CC'] = cc;
      if (arch == 'arm') {
        env['GOARM'] = '7';
      }
      buildMode = 'c-shared';
      // with_gvisor: required for TUN fd mode (file-descriptor) on Android.
      // Without it, mihomo can't start the gVisor userspace TCP/IP stack and
      // TUN listening fails with "gVisor is not included in this build".
      extraArgs = ['-tags', 'with_gvisor'];
      break;

    // -----------------------------------------------------------------
    // iOS — must be c-archive (static library)
    // -----------------------------------------------------------------
    case 'ios':
      if (arch != 'arm64') {
        throw Exception('iOS only supports arm64');
      }
      final sdkResult =
          Process.runSync('xcrun', ['--sdk', 'iphoneos', '--show-sdk-path']);
      if (sdkResult.exitCode != 0) {
        throw Exception(
          'Cannot find iOS SDK. Install Xcode from the App Store.\n'
          'Command Line Tools alone are not enough — Xcode.app with iOS SDK is required.',
        );
      }
      final sdkPath = (sdkResult.stdout as String).trim();
      final ccResult =
          Process.runSync('xcrun', ['--sdk', 'iphoneos', '--find', 'clang']);
      final cc = (ccResult.stdout as String).trim();

      env['GOOS'] = 'ios';
      env['GOARCH'] = 'arm64';
      env['CC'] = cc;
      env['CGO_CFLAGS'] =
          '-isysroot $sdkPath -arch arm64 -miphoneos-version-min=15.0';
      env['CGO_LDFLAGS'] =
          '-isysroot $sdkPath -arch arm64 -miphoneos-version-min=15.0';
      buildMode = 'c-archive';
      // with_gvisor: required for TUN fd mode (file-descriptor) on iOS.
      // Same requirement as Android — without it, mihomo fails to initialize
      // the gVisor userspace TCP/IP stack when config has "stack: gvisor",
      // causing the PacketTunnel extension to crash after reporting connected.
      extraArgs = ['-tags', 'with_gvisor'];
      break;

    // -----------------------------------------------------------------
    // macOS
    // -----------------------------------------------------------------
    case 'macos':
      env['GOOS'] = 'darwin';
      env['GOARCH'] = goArch;
      if (arch == 'amd64' && hostArch == 'arm64') {
        env['CC'] = 'clang -arch x86_64';
      } else if (arch == 'arm64' && hostArch == 'amd64') {
        env['CC'] = 'clang -arch arm64';
      }
      buildMode = 'c-shared';
      break;

    // -----------------------------------------------------------------
    // Windows
    // -----------------------------------------------------------------
    case 'windows':
      env['GOOS'] = 'windows';
      env['GOARCH'] = goArch;
      if (hostOS != 'windows') {
        if (arch == 'amd64') {
          env['CC'] = 'x86_64-w64-mingw32-gcc';
        } else if (arch == 'arm64') {
          env['CC'] = 'aarch64-w64-mingw32-gcc';
        }
        // Verify cross-compiler exists
        final cc = env['CC']!;
        final check = Process.runSync('which', [cc.split(' ').first]);
        if (check.exitCode != 0) {
          throw Exception(
            'Cross-compiler "$cc" not found.\n'
            'Install: brew install mingw-w64',
          );
        }
      }
      buildMode = 'c-shared';
      break;

    // -----------------------------------------------------------------
    // Linux
    // -----------------------------------------------------------------
    case 'linux':
      env['GOOS'] = 'linux';
      env['GOARCH'] = goArch;
      buildMode = 'c-shared';
      break;

    default:
      throw Exception('Unknown platform: $platform');
  }

  print('');
  print('═══════════════════════════════════════════════════════');
  print('  Building YueLink core');
  print('  Platform : $platform');
  print('  Arch     : $arch (GOARCH=$goArch)');
  print('  Mode     : $buildMode');
  print('  Output   : $outPath');
  print('  Debug    : $debug');
  print('═══════════════════════════════════════════════════════');

  await run(
    'go',
    [
      'build',
      '-buildmode=$buildMode',
      '-trimpath',
      '-ldflags=${ldflags.join(" ")}',
      ...extraArgs,
      '-o',
      '../$outPath', // relative to core/
      '.',
    ],
    environment: env,
    workingDirectory: corePath,
  );

  final fileSize = File(outPath).lengthSync();
  final sizeMb = (fileSize / 1024 / 1024).toStringAsFixed(1);
  print('\n Built successfully: $outPath ($sizeMb MB)');
}

/// Build all architectures for a given platform.
Future<void> buildPlatformAll(String platform, {required bool debug}) async {
  final arches = outputNames[platform]!.keys.toList();
  for (final arch in arches) {
    await buildCore(platform: platform, arch: arch, debug: debug);
    if (serviceHelperOutputNames.containsKey(platform) &&
        serviceHelperOutputNames[platform]!.containsKey(arch)) {
      await buildDesktopServiceHelper(
        platform: platform,
        arch: arch,
        debug: debug,
      );
      await buildDesktopMihomoBinary(
        platform: platform,
        arch: arch,
        debug: debug,
      );
    }
  }
}

Future<void> buildDesktopServiceHelper({
  required String platform,
  required String arch,
  required bool debug,
}) async {
  final outName = serviceHelperOutputNames[platform]?[arch];
  if (outName == null) return;

  final outPath = '$serviceOutputDir/$outName';
  File(outPath).parent.createSync(recursive: true);

  final env = <String, String>{
    'CGO_ENABLED': '0',
    'GOOS': platform == 'macos' ? 'darwin' : platform,
    'GOARCH': goArchMap[arch] ?? arch,
  };
  final ldflags = <String>[
    if (!debug) '-s',
    if (!debug) '-w',
  ];

  print('');
  print('═══════════════════════════════════════════════════════');
  print('  Building YueLink desktop service helper');
  print('  Platform : $platform');
  print('  Arch     : $arch');
  print('  Output   : $outPath');
  print('═══════════════════════════════════════════════════════');

  await run(
    'go',
    [
      'build',
      '-trimpath',
      '-ldflags=${ldflags.join(" ")}',
      '-o',
      '../$outPath',
      '.',
    ],
    environment: env,
    workingDirectory: servicePath,
  );
}

Future<void> buildDesktopMihomoBinary({
  required String platform,
  required String arch,
  required bool debug,
}) async {
  final outName = serviceMihomoOutputNames[platform]?[arch];
  if (outName == null) return;

  final outPath = '$serviceOutputDir/$outName';
  File(outPath).parent.createSync(recursive: true);

  final env = <String, String>{
    'CGO_ENABLED': '0',
    'GOOS': platform == 'macos' ? 'darwin' : platform,
    'GOARCH': goArchMap[arch] ?? arch,
  };
  final ldflags = <String>[
    if (!debug) '-s',
    if (!debug) '-w',
    '-X',
    'github.com/metacubex/mihomo/constant.Version=yuelink',
  ];

  print('');
  print('═══════════════════════════════════════════════════════');
  print('  Building YueLink desktop mihomo binary');
  print('  Platform : $platform');
  print('  Arch     : $arch');
  print('  Output   : $outPath');
  print('═══════════════════════════════════════════════════════');

  await run(
    'go',
    [
      'build',
      '-trimpath',
      '-tags',
      'with_gvisor',
      '-ldflags=${ldflags.join(" ")}',
      '-o',
      '../../$outPath',
      '.',
    ],
    environment: env,
    workingDirectory: '$corePath/mihomo',
  );
}

/// Create a macOS universal binary from arm64 + amd64 dylibs using lipo.
Future<void> _createMacOSUniversal() async {
  const arm64 = '$outputDir/macos-arm64/libclash.dylib';
  const amd64 = '$outputDir/macos-amd64/libclash.dylib';
  const universal = '$outputDir/macos-universal/libclash.dylib';

  if (!File(arm64).existsSync() || !File(amd64).existsSync()) {
    print('Skipping universal binary: need both arm64 and amd64 builds.');
    return;
  }

  File(universal).parent.createSync(recursive: true);

  await run('lipo', [
    '-create',
    arm64,
    amd64,
    '-output',
    universal,
  ]);

  final fileSize = File(universal).lengthSync();
  final sizeMb = (fileSize / 1024 / 1024).toStringAsFixed(1);
  print('\n Created universal binary: $universal ($sizeMb MB)');
}

Future<void> _createMacOSServiceUniversal(
  String arm64,
  String amd64,
  String output,
) async {
  if (!File(arm64).existsSync() || !File(amd64).existsSync()) {
    return;
  }

  File(output).parent.createSync(recursive: true);
  await run('lipo', [
    '-create',
    arm64,
    amd64,
    '-output',
    output,
  ]);
}

/// Copy built libraries to the correct Flutter platform directories.
Future<void> installLibraries(String platform) async {
  switch (platform) {
    case 'android':
      final archDirMap = {
        'arm64': 'arm64-v8a',
        'arm': 'armeabi-v7a',
        'amd64': 'x86_64',
      };
      for (final entry in archDirMap.entries) {
        final src = '$outputDir/android-${entry.key}/libclash.so';
        final dst = 'android/app/src/main/jniLibs/${entry.value}/libclash.so';
        if (File(src).existsSync()) {
          File(dst).parent.createSync(recursive: true);
          File(src).copySync(dst);
          print('Installed: $dst');
        }
      }
      break;

    case 'ios':
      const src = '$outputDir/ios-arm64/libclash.a';
      const dst = 'ios/Frameworks/libclash.a';
      if (File(src).existsSync()) {
        File(dst).parent.createSync(recursive: true);
        File(src).copySync(dst);
        print('Installed: $dst');
      }
      const hSrc = '$outputDir/ios-arm64/libclash.h';
      const hDst = 'ios/Frameworks/libclash.h';
      if (File(hSrc).existsSync()) {
        File(hSrc).copySync(hDst);
        print('Installed: $hDst');
      }
      break;

    case 'macos':
      // Prefer universal binary if both arches were built
      const arm64 = '$outputDir/macos-arm64/libclash.dylib';
      const amd64 = '$outputDir/macos-amd64/libclash.dylib';

      if (File(arm64).existsSync() && File(amd64).existsSync()) {
        // Create universal binary via lipo and install that
        await _createMacOSUniversal();
        const universalSrc = '$outputDir/macos-universal/libclash.dylib';
        const dst = 'macos/Frameworks/libclash.dylib';
        File(dst).parent.createSync(recursive: true);
        File(universalSrc).copySync(dst);
        print('Installed universal: $dst');

        // Also install per-arch for fallback loading
        File(arm64).copySync('macos/Frameworks/libclash-arm64.dylib');
        File(amd64).copySync('macos/Frameworks/libclash-amd64.dylib');
        print('Installed: macos/Frameworks/libclash-arm64.dylib');
        print('Installed: macos/Frameworks/libclash-amd64.dylib');
      } else {
        // Only one arch available
        for (final arch in ['arm64', 'amd64']) {
          final src = '$outputDir/macos-$arch/libclash.dylib';
          final dst = 'macos/Frameworks/libclash-$arch.dylib';
          if (File(src).existsSync()) {
            File(dst).parent.createSync(recursive: true);
            File(src).copySync(dst);
            print('Installed: $dst');
          }
        }
      }

      const helperArm64 =
          '$serviceOutputDir/macos-arm64/yuelink-service-helper';
      const helperAmd64 =
          '$serviceOutputDir/macos-amd64/yuelink-service-helper';
      const helperUniversal =
          '$serviceOutputDir/macos-universal/yuelink-service-helper';
      const mihomoArm64 = '$serviceOutputDir/macos-arm64/yuelink-mihomo';
      const mihomoAmd64 = '$serviceOutputDir/macos-amd64/yuelink-mihomo';
      const mihomoUniversal =
          '$serviceOutputDir/macos-universal/yuelink-mihomo';

      if (File(helperArm64).existsSync() && File(helperAmd64).existsSync()) {
        await _createMacOSServiceUniversal(
          helperArm64,
          helperAmd64,
          helperUniversal,
        );
      }
      if (File(mihomoArm64).existsSync() && File(mihomoAmd64).existsSync()) {
        await _createMacOSServiceUniversal(
          mihomoArm64,
          mihomoAmd64,
          mihomoUniversal,
        );
      }

      final helperSrc = File(helperUniversal).existsSync()
          ? helperUniversal
          : (File(helperArm64).existsSync() ? helperArm64 : helperAmd64);
      final mihomoSrc = File(mihomoUniversal).existsSync()
          ? mihomoUniversal
          : (File(mihomoArm64).existsSync() ? mihomoArm64 : mihomoAmd64);

      if (File(helperSrc).existsSync()) {
        const dst = 'macos/Frameworks/yuelink-service-helper';
        File(dst).parent.createSync(recursive: true);
        File(helperSrc).copySync(dst);
        print('Installed: $dst');
      }
      if (File(mihomoSrc).existsSync()) {
        const dst = 'macos/Frameworks/yuelink-mihomo';
        File(dst).parent.createSync(recursive: true);
        File(mihomoSrc).copySync(dst);
        print('Installed: $dst');
      }
      break;

    case 'windows':
      for (final arch in ['amd64', 'arm64']) {
        final src = '$outputDir/windows-$arch/libclash.dll';
        final dst = 'windows/libs/$arch/libclash.dll';
        if (File(src).existsSync()) {
          File(dst).parent.createSync(recursive: true);
          File(src).copySync(dst);
          print('Installed: $dst');
        }
      }
      for (final arch in ['amd64', 'arm64']) {
        final helperSrc =
            '$serviceOutputDir/windows-$arch/yuelink-service-helper.exe';
        final mihomoSrc = '$serviceOutputDir/windows-$arch/yuelink-mihomo.exe';
        final helperDst = 'windows/libs/$arch/yuelink-service-helper.exe';
        final mihomoDst = 'windows/libs/$arch/yuelink-mihomo.exe';
        if (File(helperSrc).existsSync()) {
          File(helperDst).parent.createSync(recursive: true);
          File(helperSrc).copySync(helperDst);
          print('Installed: $helperDst');
        }
        if (File(mihomoSrc).existsSync()) {
          File(mihomoDst).parent.createSync(recursive: true);
          File(mihomoSrc).copySync(mihomoDst);
          print('Installed: $mihomoDst');
        }
      }
      break;

    case 'linux':
      // Install the host-arch .so to linux/libs/ for CMake to bundle.
      for (final arch in ['amd64', 'arm64']) {
        final src = '$outputDir/linux-$arch/libclash.so';
        if (File(src).existsSync()) {
          const dst = 'linux/libs/libclash.so';
          File(dst).parent.createSync(recursive: true);
          File(src).copySync(dst);
          print('Installed: $dst');
          break; // one arch per build
        }
      }
      // Install the host-arch service helper + mihomo binary to linux/libs/
      // so the post-build step in CI (or developer install) can pick them up
      // and copy them next to the yuelink executable in the bundle.
      for (final arch in ['amd64', 'arm64']) {
        final helperSrc = '$serviceOutputDir/linux-$arch/yuelink-service-helper';
        final mihomoSrc = '$serviceOutputDir/linux-$arch/yuelink-mihomo';
        if (File(helperSrc).existsSync()) {
          const dst = 'linux/libs/yuelink-service-helper';
          File(dst).parent.createSync(recursive: true);
          File(helperSrc).copySync(dst);
          // Preserve executable bit
          Process.runSync('chmod', ['+x', dst]);
          print('Installed: $dst');
        }
        if (File(mihomoSrc).existsSync()) {
          const dst = 'linux/libs/yuelink-mihomo';
          File(dst).parent.createSync(recursive: true);
          File(mihomoSrc).copySync(dst);
          Process.runSync('chmod', ['+x', dst]);
          print('Installed: $dst');
        }
        if (File(helperSrc).existsSync() || File(mihomoSrc).existsSync()) {
          break; // one arch per build
        }
      }
      break;
  }
}

/// Remove all build artifacts.
void cleanBuild() {
  final dir = Directory(outputDir);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
    print('Cleaned: $outputDir');
  } else {
    print('Nothing to clean.');
  }

  final serviceDir = Directory(serviceOutputDir);
  if (serviceDir.existsSync()) {
    serviceDir.deleteSync(recursive: true);
    print('Cleaned: $serviceOutputDir');
  }

  final installDirs = [
    'android/app/src/main/jniLibs',
    'ios/Frameworks',
    'macos/Frameworks',
    'windows/libs',
    'linux/libs',
  ];
  for (final path in installDirs) {
    final d = Directory(path);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
      print('Cleaned: $path');
    }
  }
}

// ---------------------------------------------------------------------------
// Dependency check
// ---------------------------------------------------------------------------

/// Print what toolchains are available and what's missing.
void checkDeps() {
  print('YueLink Build Dependencies\n');

  // Go
  final goCheck = Process.runSync('go', ['version']);
  if (goCheck.exitCode == 0) {
    print('  [OK] Go: ${(goCheck.stdout as String).trim()}');
  } else {
    print('  [MISSING] Go — install from https://go.dev/dl/');
  }

  // Host info
  print('  [INFO] Host: $hostOS $hostArch');

  // macOS SDK (for macOS build)
  if (Platform.isMacOS) {
    final macSdk =
        Process.runSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
    if (macSdk.exitCode == 0) {
      print('  [OK] macOS SDK: ${(macSdk.stdout as String).trim()}');
    } else {
      print('  [MISSING] macOS SDK — install Xcode Command Line Tools');
    }

    // iOS SDK (for iOS build)
    final iosSdk =
        Process.runSync('xcrun', ['--sdk', 'iphoneos', '--show-sdk-path']);
    if (iosSdk.exitCode == 0) {
      print('  [OK] iOS SDK: ${(iosSdk.stdout as String).trim()}');
    } else {
      print('  [MISSING] iOS SDK — install Xcode from App Store');
    }

    // lipo (for universal binary)
    final lipo = Process.runSync('which', ['lipo']);
    if (lipo.exitCode == 0) {
      print('  [OK] lipo: ${(lipo.stdout as String).trim()}');
    }
  }

  // Android NDK
  try {
    final ndk = resolveAndroidNdk();
    print('  [OK] Android NDK: $ndk');
  } catch (_) {
    print(
        '  [MISSING] Android NDK — set ANDROID_HOME or install via Android Studio');
  }

  // MinGW (for Windows cross-compile)
  if (!Platform.isWindows) {
    final mingw64 = Process.runSync('which', ['x86_64-w64-mingw32-gcc']);
    if (mingw64.exitCode == 0) {
      print('  [OK] MinGW x86_64: ${(mingw64.stdout as String).trim()}');
    } else {
      print('  [MISSING] MinGW x86_64 — brew install mingw-w64');
    }
  }

  // Core submodule
  if (Directory('$corePath/mihomo').existsSync()) {
    print('  [OK] mihomo submodule: core/mihomo/');
  } else {
    print('  [MISSING] mihomo submodule — git submodule update --init');
  }

  print('');
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

void printUsage() {
  print('''
YueLink Build Tool

Usage:
  dart setup.dart <command> [options]

Commands:
  build     Build the Go core library
  install   Copy built libraries to Flutter platform directories
  check     Check build dependencies and toolchains
  clean     Remove all build artifacts

Build options:
  -p, --platform   android | ios | macos | windows | all
  -a, --arch       arm64 | amd64 | arm (default: all arches for the platform)
  --debug          Include debug symbols

Examples:
  dart setup.dart check                           # Check toolchain status
  dart setup.dart build -p android               # Build all Android arches
  dart setup.dart build -p android -a arm64       # Build Android arm64 only
  dart setup.dart build -p ios                    # Build iOS (arm64 only)
  dart setup.dart build -p macos                  # Build macOS (arm64 + amd64)
  dart setup.dart build -p windows -a amd64       # Build Windows x64
  dart setup.dart install -p macos                # lipo universal + copy
  dart setup.dart clean                           # Remove all artifacts
''');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    printUsage();
    exit(1);
  }

  final command = args[0];

  // Parse flags
  String? platform;
  String? arch;
  bool debug = false;

  for (int i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '-p':
      case '--platform':
        platform = args[++i];
        break;
      case '-a':
      case '--arch':
        arch = args[++i];
        break;
      case '--debug':
        debug = true;
        break;
      default:
        print('Unknown option: ${args[i]}');
        printUsage();
        exit(1);
    }
  }

  switch (command) {
    case 'check':
      checkDeps();
      break;

    case 'build':
      if (platform == null) {
        print('Error: --platform is required for build command.');
        exit(1);
      }

      // Verify Go is installed
      final goCheck = Process.runSync('go', ['version']);
      if (goCheck.exitCode != 0) {
        print('Error: Go is not installed or not in PATH.');
        print('Install Go from https://go.dev/dl/');
        exit(1);
      }
      print('Go: ${(goCheck.stdout as String).trim()}');

      // Verify core directory exists
      if (!Directory(corePath).existsSync()) {
        print('Error: core/ directory not found.');
        print('Run: cd core && git submodule update --init');
        exit(1);
      }

      if (platform == 'all') {
        for (final p in outputNames.keys) {
          try {
            await buildPlatformAll(p, debug: debug);
          } catch (e) {
            print('\n[WARN] Skipping $p: $e');
          }
        }
      } else if (arch != null) {
        await buildCore(platform: platform, arch: arch, debug: debug);
        if (serviceHelperOutputNames.containsKey(platform) &&
            serviceHelperOutputNames[platform]!.containsKey(arch)) {
          await buildDesktopServiceHelper(
            platform: platform,
            arch: arch,
            debug: debug,
          );
          await buildDesktopMihomoBinary(
            platform: platform,
            arch: arch,
            debug: debug,
          );
        }
      } else {
        await buildPlatformAll(platform, debug: debug);
      }
      break;

    case 'install':
      if (platform == null) {
        print('Error: --platform is required for install command.');
        exit(1);
      }
      if (platform == 'all') {
        for (final p in outputNames.keys) {
          await installLibraries(p);
        }
      } else {
        await installLibraries(platform);
      }
      break;

    case 'clean':
      cleanBuild();
      break;

    default:
      print('Unknown command: $command');
      printUsage();
      exit(1);
  }
}
