import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  static const _slides = [
    (
      title: 'Learning feels better when it fits you.',
      body: 'Sahlha turns classroom lessons into small steps, practice, and gentle support.',
      icon: Icons.auto_stories_outlined,
    ),
    (
      title: 'Same curriculum. Different path.',
      body: 'You learn the same skills as your class — at a pace and in a way that works for you.',
      icon: Icons.route_outlined,
    ),
    (
      title: 'Practice, feedback, mastery.',
      body: 'Short practice, calm feedback, and clear progress. One step at a time.',
      icon: Icons.check_circle_outline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: SahlhaLogo(size: 40),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) {
                    final slide = _slides[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: SahlhaColors.tealSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            slide.icon,
                            size: 56,
                            color: SahlhaColors.teal,
                          ),
                        ),
                        const SizedBox(height: SahlhaSpacing.xxl),
                        Text(
                          slide.title,
                          style: text.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SahlhaSpacing.md),
                        Text(
                          slide.body,
                          style: text.bodyLarge?.copyWith(
                            color: SahlhaColors.muted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => Container(
                    width: _index == i ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _index == i
                          ? SahlhaColors.teal
                          : SahlhaColors.line,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SahlhaSpacing.xl),
              SahlhaPrimaryButton(
                label: _index == _slides.length - 1 ? 'Get started' : 'Next',
                onPressed: () {
                  if (_index == _slides.length - 1) {
                    context.go('/role');
                  } else {
                    _pages.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
              const SizedBox(height: SahlhaSpacing.sm),
              TextButton(
                onPressed: () => context.go('/login?role=student'),
                child: const Text('I already have an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
