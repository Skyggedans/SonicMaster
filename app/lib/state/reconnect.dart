import 'dart:async'; // unawaited

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_model.dart';
import '../device/transport.dart';
import 'connection_prefs.dart';
import 'data_providers.dart';
import 'device_providers.dart';
import 'preset_providers.dart';

/// Open [target] on the current transport and, unless the transport changed
/// mid-await, mark the connection live, set [statusOnSuccess], and sync device
/// state. Returns true on success, false if the transport switched during the
/// connect (caller should bail — the switch already reset state + rebuilt the
/// service). Throws on a connect failure (caller decides retry/status).
Future<bool> connectAndSync(
  WidgetRef ref, {
  String? target,
  required String statusOnSuccess,
}) async {
  final kind = ref.read(transportKindProvider);

  await ref.read(deviceServiceProvider).connect(target: target);

  if (ref.read(transportKindProvider) != kind) return false;

  ref.read(connectionStateProvider.notifier).state = true;

  final String resolvedName;

  if (kind == .ble) {
    final name = target ?? 'Smart Box BLE';

    ref.read(lastBleTargetProvider.notifier).state = name;
    resolvedName = name;
  } else {
    // USB: show the real platform port name, falling back to the match.
    final match = target ?? 'Smart Box';

    resolvedName = await usbInputPortName(match) ?? match;
  }

  ref.read(connectedDeviceNameProvider.notifier).state = resolvedName;

  // Identify the model from the connection name so the pickers can gate on it.
  // Fails open to unknown (full effect set) if the data isn't loaded yet.
  final caps = ref.read(dataAssetsProvider).valueOrNull?.capabilities;

  ref.read(detectedDeviceModelProvider.notifier).state =
      caps?.detect(name: resolvedName, kind: kind) ?? DeviceModel.unknown;

  ref.read(presetLoadStatusProvider.notifier).state = statusOnSuccess;
  // Enter the pedal's edit session (020300) first, exactly as the official tool
  // does on connect — required for it to commit User-IR writes to flash. Skipped
  // if a load is already in flight (matches the other connect-time reads, which
  // self-skip on the loading flag).
  if (!ref.read(presetLoadingProvider)) {
    await ref.read(deviceServiceProvider).enterEditSession();
  }

  await refreshGlobalSettings(ref);
  unawaited(refreshNames(ref));

  return true;
}

/// Connects to [target] over the current transport and, on success, persists
/// the intent for next-launch auto-connect. A prefs-write failure is swallowed:
/// a persistence error must not report the live connection as failed. Used by
/// the Connect button after the device picker returns a target.
Future<void> connectAndPersist(WidgetRef ref, {String? target}) async {
  final kind = ref.read(transportKindProvider);

  try {
    // false => the user flipped transport during connect; bail (nothing was
    // marked live, so don't arm a stale profile).
    if (!await connectAndSync(
      ref,
      target: target,
      statusOnSuccess: 'connected',
    )) {
      return;
    }
  } catch (e) {
    ref.read(presetLoadStatusProvider.notifier).state = 'connect failed: $e';

    return;
  }

  try {
    await ref.read(connectionPrefsProvider).saveProfile(kind, target);
  } catch (_) {
    // best-effort persistence
  }
}

/// Reacts to a BLE connection-drop event and auto-reconnects to the last device
/// (bounded, backoff). The plugin only emits a drop (`false`) for an unexpected
/// disconnect — a user disconnect / transport switch / reconnect aborts the
/// monitor first — so this always attempts reconnection when BLE.
Future<void> handleConnectionDrop(WidgetRef ref) async {
  ref.read(connectionStateProvider.notifier).state = false;
  ref.read(detectedDeviceModelProvider.notifier).state = .unknown;
  final target = ref.read(lastBleTargetProvider);

  if (ref.read(transportKindProvider) != .ble || target == null) {
    ref.read(presetLoadStatusProvider.notifier).state = 'disconnected';

    return;
  }

  if (ref.read(reconnectingProvider)) return; // a retry loop is already running

  ref.read(reconnectingProvider.notifier).state = true;

  try {
    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      // Bail if the user switched transport or reconnected another way.
      if (ref.read(transportKindProvider) != .ble) return;

      if (ref.read(connectionStateProvider)) return;

      ref.read(presetLoadStatusProvider.notifier).state =
          'connection lost — reconnecting ($attempt/3)…';
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));

      if (ref.read(transportKindProvider) != .ble) return;

      try {
        // Re-reads the service each iteration (rebuilt on transport switch). A
        // false return means the user switched transport mid-connect — bail
        // rather than mark a torn-down BLE service live.
        await connectAndSync(
          ref,
          target: target,
          statusOnSuccess: 'reconnected',
        );

        return;
      } catch (e) {
        lastError = e;
      }
    }

    ref.read(presetLoadStatusProvider.notifier).state =
        'reconnect failed ($lastError) — tap Connect';
  } finally {
    ref.read(reconnectingProvider.notifier).state = false;
  }
}

/// Provider-state effects of a user-initiated disconnect (no device I/O):
/// clears the BLE reconnect target so a resulting drop event won't
/// auto-reconnect (the `handleConnectionDrop` guard sees `target == null`),
/// and marks the UI disconnected. Extracted for unit-testing without a device.
void applyUserDisconnect(WidgetRef ref) {
  ref.read(lastBleTargetProvider.notifier).state = null;
  ref.read(connectionStateProvider.notifier).state = false;
  ref.read(detectedDeviceModelProvider.notifier).state = .unknown;
  ref.read(presetLoadStatusProvider.notifier).state = 'disconnected';
}

/// State effects of a DETECTED USB connection loss (cable pull, power-off, port
/// vanished): mark disconnected, reset the model + shown name, and prompt a
/// manual reconnect — USB has no auto-reconnect. A distinct status from a user
/// disconnect so the UI reads as an unexpected loss.
void handleUsbConnectionLost(WidgetRef ref) {
  ref.read(connectionStateProvider.notifier).state = false;
  ref.read(detectedDeviceModelProvider.notifier).state = .unknown;
  ref.read(connectedDeviceNameProvider.notifier).state = null;
  ref.read(presetLoadStatusProvider.notifier).state =
      'connection lost — tap Connect';
}

/// Liveness check for the heartbeat: if the transport is USB and marked
/// connected but its port is no longer enumerable, flip to disconnected. Acts
/// only on a DEFINITIVE absence (enumeration succeeded, port gone) so a transient
/// enumeration failure can't false-trip a disconnect; re-checks the guards after
/// the async gap. [probe] is injectable for tests (defaults to the real USB port
/// enumeration).
Future<void> checkUsbLiveness(
  WidgetRef ref, {
  Future<bool?> Function(String match) probe = usbInputPortPresent,
}) async {
  if (ref.read(transportKindProvider) != .usb ||
      !ref.read(connectionStateProvider)) {
    return;
  }

  final name = ref.read(connectedDeviceNameProvider);

  if (name == null) return;

  final present = await probe(name);

  if (present == false &&
      ref.read(transportKindProvider) == .usb &&
      ref.read(connectionStateProvider)) {
    handleUsbConnectionLost(ref);
  }
}

/// The connection heartbeat (driven by a periodic timer while connected): detect
/// a silent USB drop, then poll the pedal for on-device global-settings changes.
/// Skips the poll if the liveness check just disconnected.
Future<void> deviceHeartbeat(WidgetRef ref) async {
  if (!ref.read(connectionStateProvider)) return;

  await checkUsbLiveness(ref);

  if (ref.read(connectionStateProvider)) await pollGlobalSettings(ref);
}

/// Startup auto-connect: if the user's last intent was "connected", restore the
/// transport (+ BLE target) and reconnect. On failure, BLE retries via the
/// existing backoff ([handleConnectionDrop]); USB reports a status and stays
/// disconnected. No-op when the user disconnected manually last session.
Future<void> autoConnectOnStartup(WidgetRef ref) async {
  final profile = ref.read(connectionPrefsProvider).autoConnectProfile;

  if (profile == null) return;

  ref.read(transportKindProvider.notifier).state = profile.transport;

  if (profile.transport == .ble) {
    ref.read(lastBleTargetProvider.notifier).state = profile.bleName;
  }

  try {
    await connectAndSync(
      ref,
      target: profile.bleName,
      statusOnSuccess: 'connected',
    );
  } catch (_) {
    if (profile.transport == .ble) {
      await handleConnectionDrop(ref); // reuse the 3-attempt BLE backoff
    } else {
      ref.read(presetLoadStatusProvider.notifier).state =
          'auto-connect failed — tap Connect';
    }
  }
}

/// User-initiated disconnect: disarm auto-connect (best-effort), apply the
/// state effects, then close the transport — a prefs-write failure must not
/// leave the transport open.
Future<void> disconnectDevice(WidgetRef ref) async {
  applyUserDisconnect(ref);

  try {
    await ref.read(connectionPrefsProvider).clearAutoConnect();
  } catch (_) {
    // best-effort persistence; still close the transport below
  }

  await ref.read(deviceServiceProvider).disconnect();
}
