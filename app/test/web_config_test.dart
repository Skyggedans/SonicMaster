import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the installed app opens fullscreen, in landscape', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(manifest['display'], 'fullscreen');
    expect(manifest['orientation'], 'landscape');
    expect(manifest['start_url'], '.');
    expect(manifest['theme_color'], '#1A1A1A');
  });
}
