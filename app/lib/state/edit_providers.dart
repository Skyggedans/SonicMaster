import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The module whose parameters are currently being edited. There is always a
/// selection (like the web app) — it defaults to NR (module 0).
final selectedModuleProvider = StateProvider<int?>((ref) => 0);
