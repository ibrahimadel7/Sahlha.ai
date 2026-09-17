import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/student/presentation/widgets/student_bottom_navigation.dart';

/// Bottom-navigation shell. Student tabs are exactly:
/// Home / Learn / Progress / Profile (secondary items live under Profile).
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    super.key,
    required this.navigationShell,
    required this.role,
  });

  final StatefulNavigationShell navigationShell;
  final String role; // student | teacher | parent

  void _goBranch(int index) {
    if (index == navigationShell.currentIndex) return;
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (navigationShell.currentIndex != 0) {
          _goBranch(0);
        }
      },
      child: Scaffold(
        // NOTE: the shell is intentionally not wrapped in an animated
        // switcher — duplicating StatefulNavigationShell elements (even
        // briefly) breaks per-branch navigation state. Tab feedback comes
        // from the navigation bar's own indicator animation + haptics.
        body: navigationShell,
        bottomNavigationBar: role == 'student'
            ? StudentBottomNavigation(
                selectedIndex: navigationShell.currentIndex,
                onSelected: _goBranch,
              )
            : NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _goBranch,
                destinations: _destinations,
              ),
      ),
    );
  }

  List<NavigationDestination> get _destinations {
    if (role == 'teacher') {
      return const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups),
          label: 'Classrooms',
        ),
        NavigationDestination(
          icon: Icon(Icons.rate_review_outlined),
          selectedIcon: Icon(Icons.rate_review),
          label: 'Reviews',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ];
    }
    if (role == 'parent') {
      return const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.trending_up_outlined),
          selectedIcon: Icon(Icons.trending_up),
          label: 'Progress',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: 'Materials',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ];
    }
    return const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.route_outlined),
        selectedIcon: Icon(Icons.route),
        label: 'Learn',
      ),
      NavigationDestination(
        icon: Icon(Icons.trending_up_outlined),
        selectedIcon: Icon(Icons.trending_up),
        label: 'Progress',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    ];
  }
}
