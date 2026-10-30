# Test font fixtures

`noto_sans_symbols2_u2731.ttf` is Noto Sans Symbols 2 Regular (version 2.008,
Fedora's `google-noto-sans-symbols-2-fonts`) cut down to the single glyph
U+2731 HEAVY ASTERISK:

    pyftsubset NotoSansSymbols2-Regular.ttf --unicodes=U+2731 \
      --layout-features='' --no-hinting --desubroutinize --name-IDs='*'

Copyright 2022 The Noto Project Authors (https://github.com/notofonts/symbols).
Licensed under the SIL Open Font License, Version 1.1. Below its Oswald
copyright line, `app/assets/fonts/OFL.txt` is the same license text. The font's
own name table keeps the copyright and license records.

It stands in for the fallback face that the web engine fetches for "✱" after
the first layout (see `test/ui/late_fallback_font_test.dart`).
