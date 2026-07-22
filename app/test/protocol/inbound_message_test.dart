import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/protocol/inbound_message.dart';

void main() {
  test('classifies the known constants', () {
    expect(
      InboundMessage.classify('8080F00B02000100000003010400080000F7'),
      isA<AckMessage>(),
    );
    expect(
      InboundMessage.classify('8080F0070A000100000003010204050001F7'),
      isA<PresetModifiedMessage>(),
    );
    expect(
      InboundMessage.classify('8080F0070D000100000003010204050000F7'),
      isA<PresetSavedMessage>(),
    );
    expect(
      InboundMessage.classify('8080F0030601050104000200000000F7'),
      isA<TerminatorMessage>(),
    );
  });

  test('classification is case-insensitive on input', () {
    expect(
      InboundMessage.classify('8080f00b02000100000003010400080000f7'),
      isA<AckMessage>(),
    );
  });

  test('a well-formed non-constant frame is a DataFrame carrying its hex', () {
    const hex =
        '8080F0010C00010000000A0101040900000000000000000001000000000000F7';

    final msg = InboundMessage.classify(hex);

    expect(msg, isA<DataFrame>());
    expect((msg as DataFrame).hex, hex);
  });

  test('a frame without proper framing is Malformed', () {
    expect(InboundMessage.classify('DEADBEEF'), isA<MalformedFrame>());
    expect(
      InboundMessage.classify('8080F00102'),
      isA<MalformedFrame>(),
    ); // no F7 end
  });
}
