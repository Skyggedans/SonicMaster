/// A recoverable import failure (NAM/clone or IR upload), surfaced to the UI as
/// an error dialog. [isFormatError] flags model-format problems so the dialog can
/// list the supported formats (NAM only).
class ImportException implements Exception {
  const ImportException(this.message, {this.isFormatError = false});

  final String message;
  final bool isFormatError;

  @override
  String toString() => message;
}
