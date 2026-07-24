import 'crc8_smbus.dart';
import 'hex_codec.dart';

/// Wraps a write [payload] in the pedal's standard single-packet SysEx framing:
/// `8080 F0 <crc> 01 00 <ll> <payload> F7`, every byte nibble-expanded. The CRC
/// (CRC-8/SMBUS) covers the collapsed `tt=01, ss=00, ll` header plus [payload].
///
/// Shared by every `0x11`-family register write (preset fields, footswitch, …);
/// verified byte-for-byte against captured device frames.
String buildSysexWriteFrame(List<int> payload) {
  final ll = payload.length;
  final crcInput = [
    0x01,
    0x00,
    ll,
    ...payload,
  ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final crc = Crc8Smbus.ofHex(crcInput);

  final body = StringBuffer()
    ..write('F0')
    ..write(HexCodec.expandByte(crc))
    ..write(HexCodec.expandByte('01')) // tt
    ..write(HexCodec.expandByte('00')) // ss
    ..write(HexCodec.expandByte(ll.toRadixString(16)));

  for (final b in payload) {
    body.write(HexCodec.expandByte(b.toRadixString(16)));
  }

  body.write('F7');

  return '8080${body.toString().toLowerCase()}';
}
