// Live hardware gate — requires the Sonicake pedal connected.
// End-to-end NATIVE clone pipeline: a .nam profile is converted to a .clo by the
// Rust generator (no vendor DLL), uploaded into User Profile 1 (slot 0) via the
// reverse-engineered opcode-0x25 transport, and the slot name is read back.
// OVERWRITES User Profile 1 — use only with that slot free.
// Run: flutter test integration_test/clone_upload_test.dart -d linux

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonicmaster/device/device_service.dart';
import 'package:sonicmaster/device/transport_packages.dart';
import 'package:sonicmaster/model/data_assets.dart';
import 'package:sonicmaster/protocol/clo_generator.dart';
import 'package:sonicmaster/protocol/clo_upload_frame.dart';
import 'package:sonicmaster/protocol/name_dump_decoder.dart';
import 'package:sonicmaster/src/rust/frb_generated.dart';

const _namPath = '/home/skyggedans/Downloads/NAM/reftest/ref_wavenet_v054.nam';
const _slot = 0; // User Profile 1
const _uploadName = 'nativegen';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native .nam → .clo → User Profile 1, name reads back', (
    tester,
  ) async {
    await RustLib.init(); // the native generator bridge (app main() does this)

    final service = DeviceService(MidiCommandTransport());

    await service.init();

    final data = await DataAssets.load();

    await service.connect();
    await service.enterEditSession(); // 020300 — lets writes commit to flash

    addTearDown(service.disconnect);

    Future<String?> readSlotName() async {
      final dump = await service.requestUserNames(
        DeviceService.cloneNamesRequest,
      );

      if (dump == null) return null;

      final names = decodeUserNames(
        dump,
        data.characters,
        fallbackPrefix: 'User Profile',
      );

      return names.isNotEmpty ? names[_slot] : null;
    }

    final before = await readSlotName();

    expect(before, isNotNull, reason: 'read clone slot names');

    // Native conversion: Rust WaveNet inference + Wiener post-filter → .clo.
    final profile = await const CloGenerator().fromNam(
      File(_namPath).readAsStringSync(),
    );

    final chunks = CloUploadFrame.buildChunks(
      CloUploadFrame.buildBlob(slot: _slot, name: _uploadName, profile: profile),
    );

    final result = await service.uploadClone(chunks);

    expect(
      result,
      IrWriteResult.committed,
      reason: 'pedal ACKed every chunk and sent the clone commit',
    );

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final after = await readSlotName();

    expect(
      after,
      _uploadName,
      reason: 'User Profile 1 now shows the uploaded clone name',
    );
  });
}
