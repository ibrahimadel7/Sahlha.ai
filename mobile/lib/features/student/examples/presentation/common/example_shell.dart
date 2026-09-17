import 'package:flutter/material.dart';

import '../../../../../core/theme/sahlha_colors.dart';
import '../../../presentation/widgets/sahlha_avatar.dart';

bool reducedExampleMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

class ExampleShell extends StatelessWidget {
  const ExampleShell({
    super.key,
    required this.title,
    required this.guide,
    required this.child,
    this.onReset,
  });
  final String title, guide;
  final Widget child;
  final VoidCallback? onReset;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: SahlhaColors.borderSubtle),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              const SahlhaAvatar(
                size: 48,
                state: SahlhaAvatarState.encouraging,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(guide)),
            ],
          ),
          const SizedBox(height: 16),
          child,
          if (onReset != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onReset, child: const Text('Reset')),
            ),
        ],
      ),
    ),
  );
}

class ExampleResult extends StatelessWidget {
  const ExampleResult(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: AnimatedContainer(
      duration: reducedExampleMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SahlhaColors.aquaSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class ExampleCounter extends StatelessWidget {
  const ExampleCounter({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 12,
  });
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'Decrease $label',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Semantics(
            liveRegion: true,
            label: '$label: $value',
            child: Text('$value'),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: 'Increase $label',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ],
  );
}

class ExampleNext extends StatelessWidget {
  const ExampleNext({
    super.key,
    required this.onPressed,
    this.label = 'Next step',
  });
  final VoidCallback? onPressed;
  final String label;
  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: SahlhaColors.joyTealDark,
      minimumSize: const Size(48, 48),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}
