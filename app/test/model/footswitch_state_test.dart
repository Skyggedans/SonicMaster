import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/footswitch_assignment.dart';
import 'package:sonicmaster/model/footswitch_state.dart';

void main() {
  group('footswitchAssignmentOf', () {
    test('reads the module bit from each mask, FS1 winning a tie', () {
      expect(footswitchAssignmentOf(1 << 7, 0, 7), FootswitchAssignment.fs1);
      expect(footswitchAssignmentOf(0, 1 << 7, 7), FootswitchAssignment.fs2);
      expect(footswitchAssignmentOf(0, 0, 7), FootswitchAssignment.none);
      expect(
        footswitchAssignmentOf(1 << 7, 1 << 7, 7),
        FootswitchAssignment.fs1,
      );
      // A different module's bit doesn't count as this module's.
      expect(footswitchAssignmentOf(1 << 2, 0, 7), FootswitchAssignment.none);
    });
  });

  group('footswitchDisabledOptions — a switch is blocked only when FULL', () {
    test('empty / partly-filled switches stay selectable', () {
      expect(footswitchDisabledOptions(0, 0, 7), isEmpty);
      // FS1 holds 2 others (NR, FX1) — still room for a third.
      expect(footswitchDisabledOptions((1 << 0) | (1 << 1), 0, 7), isEmpty);
    });

    test('a switch full with 3 OTHER modules blocks this module', () {
      final full = (1 << 0) | (1 << 1) | (1 << 2); // NR + FX1 + DRV on FS1

      expect(footswitchDisabledOptions(full, 0, 7), {FootswitchAssignment.fs1});
      expect(footswitchDisabledOptions(0, full, 7), {FootswitchAssignment.fs2});
    });

    test('a full switch this module is ALREADY on is not blocked for it', () {
      final full = (1 << 0) | (1 << 1) | (1 << 7); // includes module 7

      expect(footswitchDisabledOptions(full, 0, 7), isEmpty);
    });
  });

  test('footswitchModuleCount counts set bits', () {
    expect(footswitchModuleCount(0), 0);
    expect(footswitchModuleCount(1 << 8), 1);
    expect(footswitchModuleCount((1 << 7) | (1 << 8)), 2);
  });
}
