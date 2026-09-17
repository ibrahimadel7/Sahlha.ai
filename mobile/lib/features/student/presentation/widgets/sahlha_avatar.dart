import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';
import 'sahlha_companion.dart';

export 'sahlha_companion.dart'
    show
        CompanionMood,
        SahlhaCompanion,
        SahlhaAvatarState,
        companionMoodFromAvatar;

/// Reusable joyful avatar. Thin wrapper around [SahlhaCompanion] so every
/// screen shares one visual language. Respects reduced motion via the
/// companion's own ticker guard.
class SahlhaAvatar extends StatelessWidget {
  const SahlhaAvatar({
    super.key,
    this.size = 64,
    this.state = SahlhaAvatarState.idle,
    this.mood,
    this.label,
  });

  final double size;
  final SahlhaAvatarState state;
  final CompanionMood? mood;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return SahlhaCompanion(
      size: size,
      mood: mood ?? companionMoodFromAvatar(state),
      label: label,
    );
  }
}

/// Warm supportive speech bubble used on Home, lessons and playgrounds.
/// One short message at a time (neurodivergent-first).
class SahlhaSpeechBubble extends StatelessWidget {
  const SahlhaSpeechBubble({
    super.key,
    required this.message,
    this.accent = SahlhaColors.aquaSoft,
    this.maxWidth = 260,
  });

  final String message;
  final Color accent;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
          border: Border.all(color: SahlhaColors.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: SahlhaColors.ink.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 8),
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            Flexible(
              child: Text(
                message,
                style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small avatar + bubble row, the standard welcome pattern.
class AvatarGreeting extends StatelessWidget {
  const AvatarGreeting({
    super.key,
    required this.message,
    this.avatarSize = 76,
    this.state = SahlhaAvatarState.encouraging,
    this.reversed = false,
  });

  final String message;
  final double avatarSize;
  final SahlhaAvatarState state;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final avatar = SahlhaAvatar(size: avatarSize, state: state);
    final bubble = Flexible(child: SahlhaSpeechBubble(message: message));
    if (reversed) {
      return Row(children: [bubble, const SizedBox(width: 12), avatar]);
    }
    return Row(children: [bubble, const SizedBox(width: 12), avatar]);
  }
}
