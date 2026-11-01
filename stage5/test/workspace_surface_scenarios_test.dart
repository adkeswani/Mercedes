import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/workspace_surface_scenarios.dart';

void main() {
  test('restores every legacy workspace screenshot without collisions', () {
    final names = {
      'trainer-header-identity',
      'athlete-header-identity',
      for (final surface in [
        ...trainerWorkspaceSurfaces,
        ...athleteWorkspaceSurfaces,
      ]) ...[
        surface.screenshot,
        if (surface.collapseControl != null) '${surface.screenshot}-collapsed',
      ],
    };
    expect(names, {
      'trainer-header-identity',
      'trainer-dashboard',
      'trainer-clients',
      'trainer-exercise-library',
      'trainer-exercise-library-collapsed',
      'trainer-workout-library',
      'trainer-workout-library-collapsed',
      'trainer-program-library',
      'trainer-program-library-collapsed',
      'trainer-calendar-assignments',
      'athlete-header-identity',
      'athlete-my-programs',
      'athlete-workout-history',
      'athlete-calendar',
    });
    expect(trainerWorkspaceSurfaces.length, 6);
    expect(athleteWorkspaceSurfaces.length, 3);
    for (final surface in trainerWorkspaceSurfaces) {
      expect(surface.route, startsWith('/trainer/'));
      expect(
          surface.content != null || surface.visibleContent.isNotEmpty, isTrue);
    }
    for (final surface in athleteWorkspaceSurfaces) {
      expect(surface.route, startsWith('/athlete/'));
      expect(surface.content, isNotEmpty);
    }
  });

  test('preserves dashboard filter and deferred personal-best checks', () {
    expect(trainerWorkspaceSurfaces.first.controls, {
      'All filter': false,
      'Completions filter': false,
      'Comments filter': false,
      'Reactions filter': false,
      'Programs filter': false,
      'Personal bests': true,
    });
  });

  test(
      'workout library checks real fixture content rather than first-item order',
      () {
    final workout = trainerWorkspaceSurfaces.singleWhere(
      (surface) => surface.route == '/trainer/workouts',
    );
    expect(workout.visibleContent, [
      'Browser Calendar Workout',
      'Client',
      'Full Body',
      'Browser workouts',
      'Clients',
      'Unfiled',
    ]);
  });
}
