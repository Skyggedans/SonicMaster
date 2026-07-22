import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'sonic_controls.dart';

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

  @override
  Widget build(BuildContext context) {
    final ownNode = useFocusNode();
    final node = focusNode ?? ownNode;
    final textStyle = style ?? AppText.input;

    final editable = EditableText(
      controller: controller,
      focusNode: node,
      style: textStyle,
      strutStyle: StrutStyle.fromTextStyle(textStyle),
      cursorColor: Palette.accent,
      backgroundCursorColor: Palette.textDim,
      selectionColor: Palette.accent.withValues(alpha: 0.35),
      textAlign: textAlign,
      keyboardType: keyboardType,
      autofocus: autofocus,
      maxLines: 1,
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
