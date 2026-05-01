import '../../shared/telemetry.dart';
import 'desktop_tun_state.dart';

class DesktopTunTelemetry {
  DesktopTunTelemetry._();

  static void startAttempt({
    required String platform,
    required String mode,
    required String tunStack,
    double sampleRate = 1.0,
  }) {
    Telemetry.event(
      TelemetryEvents.desktopTunStartAttemptV1,
      props: {
        'platform': platform,
        'mode': mode,
        'tun_stack': tunStack,
        'sample_rate': sampleRate.clamp(0.0, 1.0),
      },
    );
  }

  static void startResult(DesktopTunSnapshot snapshot) {
    Telemetry.event(
      TelemetryEvents.desktopTunStartResultV1,
      priority: !snapshot.runningVerified,
      props: snapshot.toTelemetryProps(),
    );
  }

  static void stopResult(DesktopTunSnapshot snapshot) {
    Telemetry.event(
      TelemetryEvents.desktopTunStopResultV1,
      priority: snapshot.state == DesktopTunState.cleanupFailed,
      props: snapshot.toTelemetryProps(),
    );
  }

  static void repairAttempt(DesktopTunSnapshot snapshot, String action) {
    Telemetry.event(
      TelemetryEvents.desktopTunRepairAttemptV1,
      props: snapshot.toTelemetryProps(repairActionOverride: action),
    );
  }

  static void repairResult(DesktopTunSnapshot snapshot, String action) {
    Telemetry.event(
      TelemetryEvents.desktopTunRepairResultV1,
      priority: !snapshot.runningVerified,
      props: snapshot.toTelemetryProps(repairActionOverride: action),
    );
  }

  static void healthSnapshot(DesktopTunSnapshot snapshot) {
    Telemetry.event(
      TelemetryEvents.desktopTunHealthSnapshotV1,
      priority: snapshot.needsRepair,
      props: snapshot.toTelemetryProps(),
    );
  }

  static void cleanupResult(DesktopTunSnapshot snapshot) {
    Telemetry.event(
      TelemetryEvents.desktopTunCleanupResultV1,
      priority: snapshot.state == DesktopTunState.cleanupFailed,
      props: snapshot.toTelemetryProps(),
    );
  }
}
