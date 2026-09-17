/// Shared premium Teacher components.
///
/// Professional, calm, modern. No botanical decorations. Sahlha avatar is
/// used sparingly (processing + empty states only).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';
import '../../../../core/theme/sahlha_spacing.dart';
import '../../../../core/widgets/sahlha_widgets.dart';

// ---------------------------------------------------------------- header
class TeacherHomeHeader extends StatelessWidget {
  const TeacherHomeHeader({
    super.key,
    required this.greetingName,
    this.onNotifications,
    this.notificationCount = 0,
  });

  final String greetingName;
  final VoidCallback? onNotifications;
  final int notificationCount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sahlha',
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Your AI curriculum studio',
                    style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                  ),
                ],
              ),
            ),
            Stack(
              children: [
                IconButton(
                  onPressed: onNotifications,
                  icon: const Icon(Icons.notifications_none_outlined),
                  style: IconButton.styleFrom(
                    backgroundColor: SahlhaColors.surfacePrimary,
                    side: const BorderSide(color: SahlhaColors.line),
                  ),
                ),
                if (notificationCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: SahlhaColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: SahlhaSpacing.lg),
        Text(
          'Good morning,',
          style: text.titleMedium?.copyWith(color: SahlhaColors.ink),
        ),
        Text(
          greetingName,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          "Here's what's happening in your classrooms today.",
          style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- stat grid
class TeacherStatGrid extends StatelessWidget {
  const TeacherStatGrid({
    super.key,
    required this.classrooms,
    required this.students,
    required this.materials,
    required this.pendingReview,
  });

  final int classrooms;
  final int students;
  final int materials;
  final int pendingReview;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: SahlhaSpacing.sm,
      crossAxisSpacing: SahlhaSpacing.sm,
      childAspectRatio: 2.1,
      children: [
        _StatTile(
          icon: Icons.groups_outlined,
          iconBg: SahlhaColors.tealSoft,
          iconFg: SahlhaColors.tealDark,
          value: '$classrooms',
          label: 'Classrooms',
        ),
        _StatTile(
          icon: Icons.person_outline,
          iconBg: const Color(0xFFE3F2FF),
          iconFg: SahlhaColors.skyDark,
          value: '$students',
          label: 'Students',
        ),
        _StatTile(
          icon: Icons.description_outlined,
          iconBg: SahlhaColors.lavenderSoft,
          iconFg: SahlhaColors.lavenderDark,
          value: '$materials',
          label: 'Materials',
        ),
        _StatTile(
          icon: Icons.rate_review_outlined,
          iconBg: SahlhaColors.warmYellowSoft,
          iconFg: SahlhaColors.warmYellowDeep,
          value: '$pendingReview',
          label: 'Pending review',
          highlight: pendingReview > 0,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(SahlhaSpacing.md),
      decoration: BoxDecoration(
        color: SahlhaColors.surfacePrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? SahlhaColors.warmYellow : SahlhaColors.line,
          width: highlight ? 1.4 : 1,
        ),
        boxShadow: SahlhaShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconFg, size: 20),
          ),
          const SizedBox(width: SahlhaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                Text(
                  label,
                  style: text.bodySmall?.copyWith(
                    color: SahlhaColors.muted,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- sections
class TeacherSectionHeader extends StatelessWidget {
  const TeacherSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class TeacherAttentionTile extends StatelessWidget {
  const TeacherAttentionTile({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SahlhaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SahlhaSpacing.md),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconFg, size: 20),
          ),
          const SizedBox(width: SahlhaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: SahlhaColors.muted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- classroom
class TeacherClassroomTile extends StatelessWidget {
  const TeacherClassroomTile({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
    required this.meta,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SahlhaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SahlhaSpacing.md),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconFg, size: 26),
          ),
          const SizedBox(width: SahlhaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                ),
                Text(
                  meta,
                  style: text.bodySmall?.copyWith(
                    color: SahlhaColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: SahlhaColors.muted),
        ],
      ),
    );
  }
}

class TeacherFilterChips extends StatelessWidget {
  const TeacherFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(o),
                selected: selected == o,
                onSelected: (_) => onSelected(o),
                selectedColor: SahlhaColors.teal,
                labelStyle: TextStyle(
                  color: selected == o ? Colors.white : SahlhaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: SahlhaColors.surfacePrimary,
                side: BorderSide(
                  color: selected == o
                      ? SahlhaColors.teal
                      : SahlhaColors.line,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- search
class TeacherSearchField extends StatelessWidget {
  const TeacherSearchField({
    super.key,
    required this.controller,
    this.hint = 'Search students…',
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: SahlhaColors.surfacePrimary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SahlhaColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SahlhaColors.line),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- badges
class EvidenceBadge extends StatelessWidget {
  const EvidenceBadge({super.key, required this.label, required this.tone});

  final String label;
  final String tone; // strong | good | moderate | pending

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (tone) {
      case 'strong':
        bg = SahlhaColors.successSoft;
        fg = SahlhaColors.success;
        break;
      case 'good':
        bg = SahlhaColors.tealSoft;
        fg = SahlhaColors.tealDark;
        break;
      case 'moderate':
        bg = SahlhaColors.warmYellowSoft;
        fg = SahlhaColors.warmYellowDeep;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = SahlhaColors.muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class ReviewPill extends StatelessWidget {
  const ReviewPill({super.key, required this.label, this.tone = 'ready'});

  final String label;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (tone) {
      case 'ready':
        bg = SahlhaColors.successSoft;
        fg = SahlhaColors.success;
        break;
      case 'processing':
        bg = SahlhaColors.warmYellowSoft;
        fg = SahlhaColors.warmYellowDeep;
        break;
      case 'attention':
        bg = SahlhaColors.softCoralSoft;
        fg = SahlhaColors.softCoralDark;
        break;
      default:
        bg = SahlhaColors.tealSoft;
        fg = SahlhaColors.tealDark;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- studio tabs
class CurriculumTabBar extends StatelessWidget {
  const CurriculumTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                label: Text(tabs[i]),
                selected: selected == i,
                onSelected: (_) => onSelected(i),
                selectedColor: SahlhaColors.tealSoft,
                labelStyle: TextStyle(
                  color: selected == i
                      ? SahlhaColors.tealDark
                      : SahlhaColors.muted,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: SahlhaColors.surfacePrimary,
                side: BorderSide(
                  color: selected == i ? SahlhaColors.teal : SahlhaColors.line,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StudioMetric extends StatelessWidget {
  const StudioMetric({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: SahlhaColors.surfacePrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SahlhaColors.line),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: valueColor ?? SahlhaColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- processing
class ProcessingStepRow extends StatelessWidget {
  const ProcessingStepRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final String title;
  final String subtitle;
  final String state; // done | active | pending

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget leading;
    switch (state) {
      case 'done':
        leading = Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: SahlhaColors.teal,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 16),
        );
        break;
      case 'active':
        leading = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: SahlhaColors.teal, width: 2.5),
            color: Colors.white,
          ),
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: SahlhaColors.teal,
            ),
          ),
        );
        break;
      default:
        leading = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: SahlhaColors.line, width: 2),
            color: Colors.white,
          ),
        );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            leading,
          ],
        ),
        const SizedBox(width: SahlhaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: state == 'pending'
                      ? SahlhaColors.muted
                      : SahlhaColors.ink,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                ),
              const SizedBox(height: SahlhaSpacing.md),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sparing, professional Sahlha mark for processing/empty states only.
/// No botanical decoration.
class SahlhaProcessingAvatar extends StatelessWidget {
  const SahlhaProcessingAvatar({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SahlhaColors.tealSoft,
        shape: BoxShape.circle,
        border: Border.all(color: SahlhaColors.teal, width: 1.5),
        boxShadow: SahlhaShadows.soft,
      ),
      child: Icon(
        Icons.smart_toy_outlined,
        color: SahlhaColors.tealDark,
        size: size * 0.5,
      ),
    );
  }
}

// ---------------------------------------------------------------- student rows
class TeacherStudentRow extends StatelessWidget {
  const TeacherStudentRow({
    super.key,
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.avatarColor,
    this.onTap,
  });

  final String initials;
  final String name;
  final String subtitle;
  final Color avatarColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SahlhaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SahlhaSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: avatarColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: text.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: SahlhaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: SahlhaColors.muted),
        ],
      ),
    );
  }
}

class TeacherSummaryTrio extends StatelessWidget {
  const TeacherSummaryTrio({
    super.key,
    required this.mastered,
    required this.developing,
    required this.needsPractice,
  });

  final int mastered;
  final int developing;
  final int needsPractice;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StudioMetric(
          value: '$mastered',
          label: 'Mastered',
          valueColor: SahlhaColors.success,
        ),
        const SizedBox(width: SahlhaSpacing.sm),
        StudioMetric(
          value: '$developing',
          label: 'Developing',
          valueColor: SahlhaColors.warmYellowDeep,
        ),
        const SizedBox(width: SahlhaSpacing.sm),
        StudioMetric(
          value: '$needsPractice',
          label: 'Needs Practice',
          valueColor: SahlhaColors.softCoralDark,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- misc
String teacherInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

Color teacherAvatarColor(String id) {
  const palette = [
    Color(0xFF0E9388),
    Color(0xFF2E7FC4),
    Color(0xFF8B6FF3),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF16A34A),
  ];
  var h = 0;
  for (var i = 0; i < id.length; i++) {
    h = (h * 31 + id.codeUnitAt(i)) % 997;
  }
  return palette[h % palette.length];
}

({IconData icon, Color bg, Color fg}) teacherSubjectIcon(String subject) {
  final s = subject.toLowerCase();
  if (s.contains('program') || s.contains('computer') || s.contains('code')) {
    return (
      icon: Icons.code_outlined,
      bg: SahlhaColors.lavenderSoft,
      fg: SahlhaColors.lavenderDark,
    );
  }
  if (s.contains('python') || s.contains('data')) {
    return (
      icon: Icons.data_object_outlined,
      bg: const Color(0xFFE3F2FF),
      fg: SahlhaColors.skyDark,
    );
  }
  if (s.contains('math')) {
    return (
      icon: Icons.calculate_outlined,
      bg: SahlhaColors.warmYellowSoft,
      fg: SahlhaColors.warmYellowDeep,
    );
  }
  if (s.contains('science') || s.contains('phys') || s.contains('chem')) {
    return (
      icon: Icons.science_outlined,
      bg: SahlhaColors.tealSoft,
      fg: SahlhaColors.tealDark,
    );
  }
  if (s.contains('english') || s.contains('arabic') || s.contains('language')) {
    return (
      icon: Icons.menu_book_outlined,
      bg: const Color(0xFFFFE8E4),
      fg: SahlhaColors.softCoralDark,
    );
  }
  return (
    icon: Icons.groups_outlined,
    bg: SahlhaColors.tealSoft,
    fg: SahlhaColors.tealDark,
  );
}

String teacherGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning,';
  if (h < 17) return 'Good afternoon,';
  return 'Good evening,';
}
