import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the compact layout's preset drawer is open. Session-only and closed
/// by default. A preset pick closes it (after the unsaved-changes check), and
/// leaving the compact layout resets it, so the drawer never comes back open.
final presetDrawerOpenProvider = StateProvider<bool>((_) => false);
