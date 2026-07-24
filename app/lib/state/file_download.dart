// Saves bytes to a user-chosen file. Native shows a save dialog and writes to
// disk (returns the path); web triggers a browser download (returns the file
// name). The conditional export picks the right side at compile time.
export 'file_download_io.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
