import 'footswitch_assignment.dart';

/// The most modules a single hardware footswitch can carry. The pedal lets each
/// switch (FS1 / FS2) toggle up to this many modules together.
const footswitchCapacity = 3;

/// How many modules a switch bitmask currently holds (popcount).
int footswitchModuleCount(int mask) =>
    mask.toRadixString(2).replaceAll('0', '').length;

/// Which switch [moduleId] is currently on, given the two masks. A module is at
/// most one of None / FS1 / FS2; FS1 wins if (unusually) both bits are set.
FootswitchAssignment footswitchAssignmentOf(
  int fs1Mask,
  int fs2Mask,
  int moduleId,
) {
  final bit = 1 << moduleId;

  if (fs1Mask & bit != 0) return .fs1;

  if (fs2Mask & bit != 0) return .fs2;

  return .none;
}

/// The switch options that must be greyed out for [moduleId]: a switch this
/// module isn't already on, that has already reached [footswitchCapacity]. (A
/// switch the module IS on stays selectable so it can keep or leave it.)
Set<FootswitchAssignment> footswitchDisabledOptions(
  int fs1Mask,
  int fs2Mask,
  int moduleId,
) {
  final bit = 1 << moduleId;

  return {
    if (fs1Mask & bit == 0 &&
        footswitchModuleCount(fs1Mask) >= footswitchCapacity)
      .fs1,
    if (fs2Mask & bit == 0 &&
        footswitchModuleCount(fs2Mask) >= footswitchCapacity)
      .fs2,
  };
}
