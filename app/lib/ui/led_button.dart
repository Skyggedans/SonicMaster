import 'package:flutter/widgets.dart';

import '../theme/app_text.dart';

/// A recessed physical push-button, styled after the pedal's lit buttons: a dark
/// housing whose perimeter reads as the side walls receding into depth, with an
/// inset front face that glows amber (an orange source behind it) when [isOn], or
/// sits dark when off. Carries an optional short [label]; [onTap] toggles (a null
/// [onTap] disables + dims it).
class LedButton extends StatelessWidget {
  const LedButton({
    super.key,
    required this.isOn,
    required this.label,
    this.onTap,
    this.height = 26,
  });

  final bool isOn;
  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height * 0.3);
    final faceRadius = BorderRadius.circular(height * 0.22);
    final wall = height * 0.17; // side-wall thickness (the recess)

    // The housing: dark, with a warm rim when lit (light spilling onto the
    // near edges of the walls) or a faint grey rim when off (so the button
    // shape stays visible in the dark).
    final housing = isOn
        ? BoxDecoration(
            borderRadius: radius,
            color: const Color(0xFFB06E38), // warm, brightly-lit side walls
            border: Border.all(color: const Color(0xFFD08A4E)),
            boxShadow: [
              BoxShadow(
                color: const Color(0x55E0600F),
                blurRadius: height,
                spreadRadius: 0.5,
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: radius,
            // A faint top-lit gradient gives the unlit button volume (the raised
            // rim catches light from above, the bottom sits in shadow) so it
            // reads as a recessed button rather than empty space.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3E362E), Color(0xFF161109)],
            ),
            border: Border.all(color: const Color(0xFF443A30)),
          );

    // The front face: the orange source glows through it, hottest at the centre
    // and deepening toward the walls; dark and slightly graded when off.
    final face = isOn
        ? BoxDecoration(
            borderRadius: faceRadius,
            // An even amber glow filling the whole face — soft warm centre (not
            // a white-hot spot) fading gently to a bright orange edge, so the
            // light spreads uniformly right up to the walls.
            gradient: const RadialGradient(
              center: Alignment(0, 0.05),
              radius: 1.4,
              colors: [
                Color(0xFFFFD46E), // soft warm centre
                Color(0xFFFCA22C),
                Color(0xFFF5881A), // bright orange edge
              ],
              stops: [0.0, 0.6, 1.0],
            ),
          )
        : BoxDecoration(
            borderRadius: faceRadius,
            // Recessed face: darkest at the top (in the rim's shadow), a touch
            // lighter at the bottom where light reaches — reinforces the depth.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0C0906), Color(0xFF1E160D)],
            ),
          );

    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: height,
            constraints: BoxConstraints(minWidth: height * 1.6),
            padding: EdgeInsets.all(wall),
            decoration: housing,
            child: Container(
              alignment: Alignment.center,
              padding: label.isEmpty
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 8),
              decoration: face,
              child: label.isEmpty
                  ? null
                  : Text(
                      label,
                      style: AppText.ledLabel.copyWith(
                        color: isOn
                            ? const Color(0xFF3A1A04)
                            : Color(0x8AFFFFFF),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
