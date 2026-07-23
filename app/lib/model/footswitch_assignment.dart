/// Which hardware footswitch a module is assigned to, if any.
///
/// The pedal has two assignable footswitches (FS1, FS2). Each is owned by at
/// most one module globally — assigning a switch to a module releases it from
/// whichever module held it before. [none] means the module reacts to neither.
enum FootswitchAssignment { none, fs1, fs2 }
