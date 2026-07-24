import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/hex_codec.dart';

void main() {
  test('expandByte prefixes each nibble with 0', () {
    expect(HexCodec.expandByte('C5'), '0C05');
    expect(HexCodec.expandByte('00'), '0000');
    expect(HexCodec.expandByte('0f'), '000F'); // case-normalized upper
  });

  test('collapseNibbles drops the leading 0 of each pair', () {
    // matches legacy replace(/0(.)/g,'$1') on expanded-nibble hex
    expect(HexCodec.collapseNibbles('0001000001'), '01001');
    expect(HexCodec.collapseNibbles('0C05'), 'C5');
  });

  test('expand then collapse round-trips a byte', () {
    expect(HexCodec.collapseNibbles(HexCodec.expandByte('A3')), 'A3');
  });
}
