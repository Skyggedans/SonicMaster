/// Nibble-expansion transforms used by the pedal's SysEx framing.
///
/// The device stores each real nibble as a byte whose high nibble is 0
/// ("expanded" form). The CRC is computed over the "collapsed" real bytes,
/// then the CRC byte is re-expanded back into the frame.
class HexCodec {
  /// Legacy `replace(/0(.)/g, r'$1')`: scan left-to-right; whenever a `0` is
  /// followed by any char, keep only that char.
  static String collapseNibbles(String expandedHex) {
    final out = StringBuffer();
    var i = 0;

    while (i < expandedHex.length) {
      if (expandedHex[i] == '0' && i + 1 < expandedHex.length) {
        out.write(expandedHex[i + 1]);
        i += 2;
      } else {
        out.write(expandedHex[i]);
        i += 1;
      }
    }

    return out.toString();
  }

  /// One byte "C5" -> "0C05": each nibble gets a leading `0`. Output uppercase.
  static String expandByte(String twoCharHex) {
    final b = twoCharHex.toUpperCase().padLeft(2, '0');

    return '0${b[0]}0${b[1]}';
  }
}
