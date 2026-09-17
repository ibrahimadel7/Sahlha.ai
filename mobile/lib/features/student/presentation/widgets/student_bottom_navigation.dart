import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';

class StudentBottomNavigation extends StatelessWidget {
  const StudentBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: SahlhaColors.surfaceRaised,
      border: Border(top: BorderSide(color: SahlhaColors.borderSubtle)),
    ),
    child: NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: SahlhaColors.surfaceRaised,
        indicatorColor: SahlhaColors.tealSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 27,
            color: states.contains(WidgetState.selected)
                ? SahlhaColors.tealDark
                : SahlhaColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 13,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? SahlhaColors.tealDark
                : SahlhaColors.ink,
          ),
        ),
      ),
      child: NavigationBar(
        height: 78,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route_rounded),
            label: 'Learn',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );
}
