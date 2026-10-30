import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/data_assets.dart';

/// Device data tables (effects, commands, modules, characters), loaded once.
final dataAssetsProvider = FutureProvider<DataAssets>(
  (ref) => DataAssets.load(),
);
