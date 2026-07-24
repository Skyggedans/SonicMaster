import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/preset_ref.dart';

void main() {
  test('all() lists 50 user + 50 factory presets', () {
    final all = PresetRef.all();

    expect(all, hasLength(100));
    expect(all.first, const PresetRef(.user, 1));
    expect(all[49], const PresetRef(.user, 50));
    expect(all[50], const PresetRef(.factory, 1));
    expect(all.last, const PresetRef(.factory, 50));
  });

  test('label formats bank + zero-padded number', () {
    expect(const PresetRef(.user, 1).label, 'P01');
    expect(const PresetRef(.factory, 50).label, 'F50');
  });

  test('value equality', () {
    expect(const PresetRef(.user, 3), const PresetRef(.user, 3));
    expect(const PresetRef(.user, 3), isNot(const PresetRef(.factory, 3)));
  });
}
