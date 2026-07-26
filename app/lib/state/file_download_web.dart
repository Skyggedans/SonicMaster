import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [bytes] as [fileName] via an object-URL
/// anchor. Returns the file name (web has no filesystem path). Extra params are
/// accepted for API parity with the native side and ignored here.
Future<String?> saveBytesFile({
  required String fileName,
  required List<int> bytes,
  String? dialogTitle,
  List<String> extensions = const [],
}) async {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );

  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;

  anchor.href = url;
  anchor.download = fileName;
  anchor.click();

  web.URL.revokeObjectURL(url);

  return fileName;
}
