import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/theme/app_text.dart';
import 'package:sonicmaster/ui/sonic_metrics.dart';

/// The work-area density tokens. Every regular value is the literal it replaces
/// (cited per line, as of the V0 baseline), so desktop and tablet stay
/// pixel-identical; compact is the D5 phone profile. The invariants keep the
/// compact numbers honest when someone tunes one of them later.
void main() {
  test('regular tokens equal the literals they replace', () {
    const metrics = SonicMetrics.regular;

    // preset_browser_page.dart:409 / :416-417 (all(12), maxHeight - 24)
    expect(metrics.workPadding, 12);
    // preset_browser_page.dart:437
    expect(metrics.chainPanelsGap, 34);
    // preset_browser_page.dart:33
    expect(metrics.minPanelHeight, 212);
    // preset_fields_panel.dart:14
    expect(metrics.presetPanelWidth, 360);
    // sonic_controls.dart:501 and the KnobControl default
    expect(metrics.panelKnobSize, 120);
    // knob_control.dart:141, sonic_controls.dart:517
    expect(metrics.knobCellPadding, 8);
    // knob_control.dart:123/:135/:154, sonic_controls.dart:521/:529
    expect(metrics.knobValueStyle, same(AppText.knobValue));
    expect(metrics.knobLabelStyle, same(AppText.knobLabel));
    // module_editor.dart:85
    expect(
      metrics.editorHeaderPadding,
      const EdgeInsets.fromLTRB(16, 12, 16, 4),
    );
    // module_editor.dart:144/:255, SonicDropdown's default height
    expect(metrics.editorControlHeight, 40);
    // module_editor.dart:227
    expect(metrics.isEffectDescriptionVisible, isTrue);
    // sonic_controls.dart:695
    expect(metrics.footswitchSegmentPadding, 16);
    // chain_view.dart:106 (min == max: the card width never varies)
    expect(metrics.chainCardMinWidth, 96);
    expect(metrics.chainCardMaxWidth, 96);
    // chain_view.dart:107
    expect(
      metrics.chainCardPadding,
      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );
    // chain_view.dart:138 / :77 / :86 / :140
    expect(metrics.chainGripGap, 6);
    expect(metrics.chainIconSize, 46);
    expect(metrics.chainIconGap, 4);
    expect(metrics.chainLedGap, 8);
    // chain_view.dart:146-150
    expect(metrics.chainLedSize, const Size(48, 16));
    // chain_view.dart:169
    expect(metrics.chainBadgeTop, 20);
    // chain_view.dart:209-210
    expect(metrics.chainConnectorIconSize, 20);
    expect(metrics.chainConnectorPadding, 2);
    // chain_view.dart:232
    expect(metrics.ampBlockPadding, 10);
  });

  test('compact tokens are the D5 phone profile', () {
    const metrics = SonicMetrics.compact;

    expect(metrics.workPadding, 8);
    expect(metrics.chainPanelsGap, 8);
    expect(metrics.minPanelHeight, 142);
    expect(metrics.presetPanelWidth, 194);
    expect(metrics.panelKnobSize, 72);
    expect(metrics.knobCellPadding, 4);
    expect(metrics.knobValueStyle, same(AppText.knobValueCompact));
    expect(metrics.knobLabelStyle, same(AppText.knobLabelCompact));
    expect(
      metrics.editorHeaderPadding,
      const EdgeInsets.fromLTRB(12, 4, 12, 4),
    );
    expect(metrics.editorControlHeight, 32);
    expect(metrics.isEffectDescriptionVisible, isFalse);
    expect(metrics.footswitchSegmentPadding, 10);
    expect(metrics.chainCardMinWidth, 54);
    expect(metrics.chainCardMaxWidth, 96);
    expect(
      metrics.chainCardPadding,
      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    );
    expect(metrics.chainGripGap, 2);
    expect(metrics.chainIconSize, 28);
    expect(metrics.chainIconGap, 2);
    expect(metrics.chainLedGap, 4);
    expect(metrics.chainLedSize, const Size(36, 12));
    expect(metrics.chainBadgeTop, -6);
    expect(metrics.chainConnectorIconSize, 16);
    expect(metrics.chainConnectorPadding, 0);
    expect(metrics.ampBlockPadding, 4);
  });

  test('a connector is its chevron plus both insets', () {
    expect(SonicMetrics.regular.chainConnectorWidth, 24);
    expect(SonicMetrics.compact.chainConnectorWidth, 16);
  });

  test('the compact knob text tokens only shrink the regular ones', () {
    expect(AppText.knobValueCompact.fontSize, 14);
    expect(AppText.knobValueCompact.fontFamily, AppText.knobValue.fontFamily);
    expect(AppText.knobValueCompact.fontWeight, AppText.knobValue.fontWeight);
    expect(AppText.knobValueCompact.color, AppText.knobValue.color);
    expect(AppText.knobLabelCompact.fontSize, 12);
    expect(AppText.knobLabelCompact.letterSpacing, 0.6);
    expect(AppText.knobLabelCompact.fontFamily, AppText.knobLabel.fontFamily);
    expect(AppText.knobLabelCompact.fontWeight, AppText.knobLabel.fontWeight);
    expect(AppText.knobLabelCompact.color, AppText.knobLabel.color);
  });

  group('invariants', () {
    for (final metrics in const [SonicMetrics.regular, SonicMetrics.compact]) {
      final mode = metrics.isCompact ? 'compact' : 'regular';

      test('$mode: a selected card at the floor still holds its drag grip', () {
        // 40-px grip (8 dots x 5 px) inside the padding and a 2-px border on
        // each side.
        expect(
          metrics.chainCardMinWidth - metrics.chainCardPadding.horizontal - 4,
          greaterThanOrEqualTo(40),
        );
      });

      test('$mode: the FS badge never pokes out of the work padding', () {
        expect(-metrics.chainBadgeTop, lessThanOrEqualTo(metrics.workPadding));
      });
    }

    test('compact minAppWidth holds the 9-card chain on one row', () {
      const metrics = SonicMetrics.compact;

      final oneRow =
          9 * metrics.chainCardMinWidth +
          8 * metrics.chainConnectorWidth +
          2 * metrics.ampBlockPadding +
          2 * metrics.workPadding;

      expect(oneRow, 638);
      expect(metrics.minAppWidth, greaterThanOrEqualTo(oneRow));
    });
  });
}
