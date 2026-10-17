import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Prompts for a save location and writes [bytes] there. Returns the chosen
/// path, or null if the user cancels.
Future<String?> saveBytesFile({
  required String fileName,
  required List<int> bytes,
  String? dialogTitle,
  List<String> extensions = const [],
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: extensions.isEmpty ? .any : .custom,
    allowedExtensions: extensions.isEmpty ? null : extensions,
  );

  if (path == null) return null;

  await File(path).writeAsBytes(bytes);

  return path;
}
