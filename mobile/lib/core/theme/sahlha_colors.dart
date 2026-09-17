import 'package:flutter/material.dart';

/// Sahlha design tokens — teal + warm off-white + graphite + small accents.
///
/// Canvas is a very light warm off-white; cards sit one tonal step above it
/// so surfaces separate without heavy shadows. Follows the Sahlha UI
/// reference (NOT botanical, NOT Duolingo).
abstract final class SahlhaColors {
  /// App canvas: very light warm off-white.
  static const Color cream = Color(0xFFFBFAF7);

  /// Primary card surface: warm white, one step above the canvas.
  static const Color surface = Color(0xFFFFFEFC);

  /// Warm accent surface for gentle highlights.
  static const Color surfaceWarm = Color(0xFFFAF5EA);

  // ---- Layered surface system (depth without heavy shadows) ----
  /// The app background. Prefer over raw [cream] in new code.
  static const Color backgroundPrimary = Color(0xFFFBFAF7);

  /// Default card surface. Prefer over raw [surface] in new code.
  static const Color surfacePrimary = Color(0xFFFFFEFC);

  /// Slightly raised surface (headers, sheets, selected rows).
  static const Color surfaceRaised = Color(0xFFFFFFFF);

  /// Very pale teal for selected / active learning surfaces.
  static const Color surfaceTealSoft = Color(0xFFEFFAF8);

  /// Very pale warm yellow for gentle emphasis.
  static const Color surfaceWarmAccent = Color(0xFFFEF6E4);

  /// Soft warm-gray border for calm separation.
  static const Color borderSubtle = Color(0xFFE7E1D4);

  static const Color teal = Color(0xFF0E9388);
  static const Color tealDark = Color(0xFF0B6E64);
  static const Color tealSoft = Color(0xFFE3F4F1);
  static const Color tealFaint = Color(0xFFEFFAF8);

  static const Color ink = Color(0xFF22313F);
  static const Color muted = Color(0xFF64748B);

  /// Default border color. Prefer [borderSubtle] in new code.
  static const Color line = Color(0xFFE7E1D4);

  static const Color sun = Color(0xFFFBBF24);
  static const Color sunSoft = Color(0xFFFEF3C7);
  static const Color coral = Color(0xFFF97066);

  // ---- Joyful Student palette (reference image target) ----
  // Keep the calm base above for Teacher/Parent; these add expressive
  // accents for the Student world only. Low-saturation surfaces guide
  // attention without overstimulation.
  /// Primary teal from the reference (~#0F9F95).
  static const Color joyTeal = Color(0xFF0F9F95);
  static const Color joyTealDark = Color(0xFF0B6E64);

  /// Secondary aqua/mint (~#49D5CC).
  static const Color aqua = Color(0xFF49D5CC);
  static const Color aquaSoft = Color(0xFFDFFBF8);

  /// Warm yellow (~#FFC94A) — current skill, gentle emphasis.
  static const Color warmYellow = Color(0xFFFFC94A);
  static const Color warmYellowSoft = Color(0xFFFFF3D1);
  static const Color warmYellowDeep = Color(0xFF956300);

  /// Lavender (~#8B6FF3) — Quick Check milestones.
  static const Color lavender = Color(0xFF8B6FF3);
  static const Color lavenderDark = Color(0xFF6A4FD0);
  static const Color lavenderSoft = Color(0xFFEEE8FF);
  static const Color lavenderFaint = Color(0xFFF4F1FA);

  /// Sky blue (~#73BFFF) — practice / examples.
  static const Color sky = Color(0xFF73BFFF);
  static const Color skyDark = Color(0xFF2E7FC4);
  static const Color skySoft = Color(0xFFE3F2FF);

  /// Soft coral (~#FF8C72) — needs practice, supportive errors.
  static const Color softCoral = Color(0xFFFF8C72);
  static const Color softCoralDark = Color(0xFFB63752);
  static const Color softCoralSoft = Color(0xFFFFE8E4);

  /// Warm cream canvas, one step warmer than [cream].
  static const Color creamWarm = Color(0xFFFFFBF2);

  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerSoft = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF0EA5E9);
  static const Color infoSoft = Color(0xFFE0F2FE);

  /// Calm status color for a student-facing mastery state.
  static Color mastery(String state) {
    return switch (state) {
      'mastered' => success,
      'developing' => teal,
      'needs_practice' => warning,
      _ => muted,
    };
  }

  static Color masterySoft(String state) {
    return switch (state) {
      'mastered' => successSoft,
      'developing' => tealSoft,
      'needs_practice' => warningSoft,
      _ => const Color(0xFFF1F5F9),
    };
  }
}

/// Restrained elevation for the student experience: barely-there shadows
/// that separate layers without any game-like floating.
abstract final class SahlhaShadows {
  static List<BoxShadow> get soft => [
    BoxShadow(
      color: SahlhaColors.ink.withValues(alpha: 0.05),
      blurRadius: 14,
      offset: const Offset(0, 5),
    ),
  ];

  static List<BoxShadow> get lifted => [
    BoxShadow(
      color: SahlhaColors.tealDark.withValues(alpha: 0.12),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ];

  static List<BoxShadow> get pressed => [
    BoxShadow(
      color: SahlhaColors.ink.withValues(alpha: 0.03),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}
