import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';

/// The soft keyboard for typing a number: digits and a decimal point, plus a
/// minus sign when [isSigned]. The web engine drops `signed` (it only emits
/// `inputmode=numeric|decimal`), and several Android keyboards then show no
/// '-', so a signed value on the web gets the full text keyboard instead. The
/// typed text is parsed the same way either way. [isWeb] is for tests.
TextInputType numericKeyboardType({
  required bool isSigned,
  bool isWeb = kIsWeb,
}) {
  if (!isSigned) return const TextInputType.numberWithOptions(decimal: true);

  return isWeb
      ? TextInputType.text
      : const TextInputType.numberWithOptions(signed: true, decimal: true);
}

/// A Material-free single-line text input: a raw [EditableText] (optionally
/// inside a recessed [SonicRecess] well) with the selection toolbar disabled,
/// so it needs no `Material` ancestor and no `MaterialLocalizations`. Typing,
/// cursor, focus, submit, and tap-outside all work; a placeholder [hintText]
/// shows while empty.
class SonicField extends HookWidget {
  const SonicField({
    super.key,
    required this.controller,
    this.focusNode,
    this.style,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.autofocus = false,
    this.maxLength,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    this.isRecessed = true,
    this.selectAllOnFocus,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final bool autofocus;
  final int? maxLength;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onTapOutside;
  final EdgeInsetsGeometry padding;
  final bool isRecessed;

  /// Whether focusing the field selects its text; null keeps the SDK default
  /// (on for web and desktop, off for native mobile).
  final bool? selectAllOnFocus;

  /// Off for numbers: a suggestion strip costs a phone's scarce height.
  final bool autocorrect;
  final bool enableSuggestions;

  /// The room kept around the caret when the field scrolls itself into view
  /// (EditableText's own default: 20 on every side).
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    final ownNode = useFocusNode();
    final node = focusNode ?? ownNode;

    // EditableText paints its style verbatim — unlike Text it does NOT merge the
    // ambient DefaultTextStyle, so a style that omits fontFamily rendered the
    // typed text in the platform default face instead of the app's Oswald (the
    // hint, a plain Text, did inherit it — hence the mismatch). Merge it here so
    // an input reads like every other piece of text in the app; anything the
    // call site sets explicitly still wins.
    final textStyle = DefaultTextStyle.of(
      context,
    ).style.merge(style ?? AppText.input);

    final editable = EditableText(
      controller: controller,
      focusNode: node,
      style: textStyle,
      // Forced, like EditableText's own default (and the TextField this
      // replaced): a fallback face that the web fetches late for a typed
      // glyph Oswald lacks can't change the line, so the intrinsics the field
      // reports keep matching its layout (a knob's value editor sits under
      // the work panels' IntrinsicHeight).
      strutStyle: StrutStyle.fromTextStyle(textStyle, forceStrutHeight: true),
      cursorColor: Palette.accent,
      backgroundCursorColor: Palette.textDim,
      selectionColor: Palette.accent.withValues(alpha: 0.35),
      textAlign: textAlign,
      keyboardType: keyboardType,
      autofocus: autofocus,
      selectAllOnFocus: selectAllOnFocus,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: 1,
      scrollPadding: scrollPadding,
      cursorOpacityAnimates: true,
      rendererIgnoresPointer: true,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      // Disable the selection toolbar so no Material/Cupertino localizations
      // are required in a widgets-only app.
      selectionControls: null,
      contextMenuBuilder: (_, _) => const SizedBox.shrink(),
    );

    // The raw render object ignores pointers (above), so an outer tap focuses
    // the field; a hint paints under the (empty) text.
    Widget content = Stack(
      children: [
        if (hintText != null)
          Positioned.fill(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isNotEmpty) return const SizedBox.shrink();

                return Align(
                  alignment: textAlign == TextAlign.center
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Text(
                    hintText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle.copyWith(color: Palette.textDim),
                  ),
                );
              },
            ),
          ),
        editable,
      ],
    );

    content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: node.requestFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Padding(padding: padding, child: content),
      ),
    );

    if (!isRecessed) return content;

    return SonicRecess(radius: 8, child: content);
  }
}
